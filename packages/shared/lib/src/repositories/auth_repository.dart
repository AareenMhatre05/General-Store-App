import 'dart:io' show SocketException;

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../supabase/supabase_bootstrap.dart';

/// Why a sign-in attempt failed, in terms a screen can act on. Screens
/// shouldn't have to know gotrue's exception types or error-code
/// strings, so [AuthRepository.signIn] translates them into this.
enum SignInFailure { emailNotConfirmed, invalidCredentials, network, unknown }

class SignInException implements Exception {
  const SignInException(this.reason);

  final SignInFailure reason;

  @override
  String toString() => 'SignInException(${reason.name})';
}

/// Raised when a mobile number already belongs to another customer
/// account. One account per number is enforced by a unique index on the
/// normalised number, so this can surface either at signup or when
/// somebody edits their profile.
class PhoneTakenException implements Exception {
  const PhoneTakenException();

  @override
  String toString() => 'PhoneTakenException';
}

/// Why an invite code was rejected. Kept separate from [SignInFailure]
/// because the advice differs completely: an expired invite needs the
/// owner to issue another one, a wrong code just needs re-typing.
enum InviteFailure { notFound, alreadyUsed, expired }

class InviteException implements Exception {
  const InviteException(this.reason);

  final InviteFailure reason;

  @override
  String toString() => 'InviteException(${reason.name})';
}

/// Which of the two join paths actually happened, so the screen can tell
/// someone whether to go and confirm their email or simply log in.
enum StaffJoinOutcome { accountCreated, existingAccountPromoted }

/// Auth is shared between both apps, but signup shapes differ:
/// customer_app never sends an invite code (always lands as
/// 'customer'); staff_app must collect one from the user (see
/// staff_invites in the DB) or signup is rejected server-side.
class AuthRepository {
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  String? get currentUserId => supabase.auth.currentUser?.id;

  /// Deep link the confirmation email sends the user back to. Declared
  /// in each app's AndroidManifest, and must also be whitelisted under
  /// Authentication → URL Configuration in the Supabase dashboard.
  static const emailRedirectTo = 'kgs://login-callback';

  /// Digits only, last ten -- the same normalisation the database
  /// applies, so "+91 87660 08705" and "08766008705" are recognised as
  /// one number here too rather than only at the constraint.
  static String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  /// True when [phone] looks like an Indian mobile number. Mirrors the
  /// database's check constraint; the constraint is the control, this is
  /// only so the person finds out before submitting.
  static bool isValidMobile(String phone) =>
      RegExp(r'^[6-9][0-9]{9}$').hasMatch(normalizePhone(phone));

  /// Whether a number is free to register. Asked before signing up,
  /// because a unique-index violation raised inside the signup trigger
  /// reaches the client as a generic "database error".
  Future<bool> isPhoneAvailable(String phone) async {
    final result = await supabase.rpc(
      'phone_available',
      params: {'p_phone': normalizePhone(phone)},
    );
    return result as bool? ?? true;
  }

  /// A customer must give a mobile number: one account per number is the
  /// rule, and a nullable column cannot express it -- a unique index
  /// permits any number of NULLs.
  Future<AuthResponse> signUpCustomer({
    required String email,
    required String password,
    required String phone,
    String? fullName,
  }) async {
    if (!isValidMobile(phone)) throw const FormatException('phone');
    if (!await isPhoneAvailable(phone)) throw const PhoneTakenException();

    try {
      return await supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: emailRedirectTo,
        data: {
          if (fullName != null) 'full_name': fullName,
          'phone': normalizePhone(phone),
        },
      );
    } on AuthException catch (e) {
      // The check above races anyone signing up with the same number in
      // the same moment; the index is what actually decides, so translate
      // its verdict rather than showing "database error".
      if (e.message.toLowerCase().contains('database error')) {
        if (!await isPhoneAvailable(phone)) throw const PhoneTakenException();
      }
      rethrow;
    }
  }

  /// Joining the team with an invite code.
  ///
  /// The code is checked before signing up rather than after, because the
  /// auth service flattens any error raised by the signup trigger into a
  /// generic "database error" -- so a wrong code and a broken server look
  /// identical to the app unless we ask first.
  ///
  /// Two paths, because the invited person may well already shop with the
  /// customer app under the same address:
  ///   * no account yet -> normal signup, the trigger promotes them
  ///   * account exists -> sign in and redeem, since the trigger only
  ///     ever runs at account creation and will never fire for them
  Future<StaffJoinOutcome> signUpStaff({
    required String email,
    required String password,
    required String inviteCode,
    String? fullName,
  }) async {
    final trimmedEmail = email.trim();
    final code = inviteCode.trim().toUpperCase();

    final status = await supabase.rpc(
      'check_staff_invite',
      params: {'p_email': trimmedEmail, 'p_code': code},
    ) as String?;
    switch (status) {
      case 'ok':
        break;
      case 'used':
        throw const InviteException(InviteFailure.alreadyUsed);
      case 'expired':
        throw const InviteException(InviteFailure.expired);
      default:
        throw const InviteException(InviteFailure.notFound);
    }

    try {
      await supabase.auth.signUp(
        email: trimmedEmail,
        password: password,
        emailRedirectTo: emailRedirectTo,
        data: {
          'invite_code': code,
          if (fullName != null) 'full_name': fullName,
        },
      );
      return StaffJoinOutcome.accountCreated;
    } on AuthException catch (e) {
      final alreadyRegistered = e.code == 'user_already_exists' ||
          e.message.toLowerCase().contains('already registered');
      if (!alreadyRegistered) rethrow;

      // Their password is their existing one; a wrong guess surfaces as
      // invalidCredentials, which the screen explains.
      await signIn(email: trimmedEmail, password: password);
      try {
        await supabase.rpc('redeem_staff_invite', params: {'p_code': code});
      } catch (_) {
        await signOut();
        rethrow;
      }
      return StaffJoinOutcome.existingAccountPromoted;
    }
  }

  /// Throws [SignInException] so callers can tell "you haven't confirmed
  /// your email yet" apart from "wrong password" -- the two need very
  /// different advice, and the email-confirmation case is common while
  /// Supabase's "Confirm email" setting is on.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await supabase.auth
          .signInWithPassword(email: email, password: password);
    } on AuthRetryableFetchException catch (_) {
      // The server was never reached -- no signal at all about whether
      // the credentials are good. Saying "check your password" here
      // sends people hunting for a problem that isn't there.
      throw const SignInException(SignInFailure.network);
    } on AuthException catch (e) {
      throw SignInException(switch (e.code) {
        'email_not_confirmed' => SignInFailure.emailNotConfirmed,
        'invalid_credentials' => SignInFailure.invalidCredentials,
        _ => SignInFailure.unknown,
      });
    } on SocketException catch (_) {
      throw const SignInException(SignInFailure.network);
    } on ClientException catch (_) {
      throw const SignInException(SignInFailure.network);
    }
  }

  Future<void> signOut() => supabase.auth.signOut();

  /// Fetches the profile row (and therefore role) for the signed-in
  /// user. Each app should call this right after sign-in and sign the
  /// user back out if the role doesn't match that app's audience.
  Future<Profile?> currentProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;

    final row =
        await supabase.from('profiles').select().eq('id', userId).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// Updates the signed-in user's own name/phone (not role -- that's
  /// locked down separately, see the profiles RLS policies).
  ///
  /// Only the fields actually passed are written. It used to send both
  /// every time, so editing just the name sent `phone: null` and wiped
  /// the number -- harmless while phone was optional, an outright
  /// constraint violation now that customers must have one.
  Future<Profile> updateProfile({String? fullName, String? phone}) async {
    final userId = currentUserId!;
    if (phone != null && !isValidMobile(phone)) {
      throw const FormatException('phone');
    }

    try {
      final row = await supabase
          .from('profiles')
          .update({
            if (fullName != null) 'full_name': fullName,
            if (phone != null) 'phone': normalizePhone(phone),
          })
          .eq('id', userId)
          .select()
          .single();
      return Profile.fromJson(row);
    } on PostgrestException catch (e) {
      // 23505 is a unique violation, which on this table can only be the
      // one-account-per-number index.
      if (e.code == '23505') throw const PhoneTakenException();
      rethrow;
    }
  }
}
