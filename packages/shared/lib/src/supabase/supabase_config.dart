/// Public Supabase project connection details.
///
/// The anon key is designed by Supabase to be embedded in client apps --
/// it has no privileges beyond what RLS policies grant. The secret
/// service_role key must never appear here or anywhere in either app.
class SupabaseConfig {
  static const String url = 'https://yswvraurldyxatjcuvxg.supabase.co';

  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlzd3ZyYXVybGR5eGF0amN1dnhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2NjMxMzMsImV4cCI6MjA5OTIzOTEzM30.WR0-Q47JpWJdcJAGh6lZii3S6mo65Ne4VZcLSTLCEoo';
}
