import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../repositories/auth_repository.dart';

enum AppAuthStatus { loading, unauthenticated, authenticated }

/// Tracks the signed-in user's session and profile/role, and notifies
/// go_router (via `refreshListenable`) whenever either changes. Both
/// apps use this directly; only the allowed-roles check in each app's
/// own router redirect differs.
class AppAuthState extends ChangeNotifier {
  AppAuthState(this._authRepository) {
    _refresh();
    _subscription = _authRepository.authStateChanges.listen((_) => _refresh());
  }

  final AuthRepository _authRepository;
  late final StreamSubscription<dynamic> _subscription;

  AppAuthStatus status = AppAuthStatus.loading;
  Profile? profile;

  Future<void> _refresh() async {
    if (_authRepository.currentUserId == null) {
      status = AppAuthStatus.unauthenticated;
      profile = null;
    } else {
      profile = await _authRepository.currentProfile();
      status = profile == null ? AppAuthStatus.unauthenticated : AppAuthStatus.authenticated;
    }
    notifyListeners();
  }

  Future<void> signOut() => _authRepository.signOut();

  /// Re-fetches the profile row -- call after an edit (e.g. updating
  /// name/phone) so the new values show up without a full re-login.
  Future<void> refreshProfile() => _refresh();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
