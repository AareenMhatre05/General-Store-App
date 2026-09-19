import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Call once, before `runApp`, in both customer_app and staff_app.
Future<void> initializeSupabase() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
}

/// Shorthand for the initialized client, used throughout the
/// repositories in this package.
SupabaseClient get supabase => Supabase.instance.client;
