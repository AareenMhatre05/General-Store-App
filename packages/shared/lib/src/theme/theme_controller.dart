import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the user wants light, dark, or whatever the phone
/// is set to.
///
/// Stored on the device rather than in the user's profile row on
/// purpose: appearance belongs to the phone, not the account. Someone
/// using the app on a bright shop floor and a dark bedroom wants
/// different answers on each, and a device-local setting also means the
/// choice survives being signed out.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._mode);

  static const _storageKey = 'appearance_mode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// Loads the saved choice before the app builds, so it never paints
  /// the wrong theme for a frame and then snaps.
  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    return ThemeController._(_parse(saved));
  }

  static ThemeMode _parse(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _serialise(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    // Repaint first, persist second: the UI should never wait on disk.
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _serialise(mode));
  }

  /// Label for the settings row.
  String get label => switch (_mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Match phone',
      };
}

/// The appearance picker, shared by both apps so the wording and
/// behaviour cannot drift apart.
Future<void> showAppearanceSheet(BuildContext context, ThemeController controller) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    builder: (sheetContext) => SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // RadioGroup rather than per-tile onChanged: the older
            // API is deprecated in current Flutter.
            RadioGroup<ThemeMode>(
              groupValue: controller.mode,
              onChanged: (value) {
                if (value != null) controller.setMode(value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in const [
                    (mode: ThemeMode.system, label: 'Match phone', icon: Icons.brightness_auto),
                    (mode: ThemeMode.light, label: 'Light', icon: Icons.light_mode_outlined),
                    (mode: ThemeMode.dark, label: 'Dark', icon: Icons.dark_mode_outlined),
                  ])
                    RadioListTile<ThemeMode>(
                      value: option.mode,
                      secondary: Icon(option.icon),
                      title: Text(option.label),
                      subtitle: option.mode == ThemeMode.system
                          ? const Text('Follows your phone’s day/night setting')
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
