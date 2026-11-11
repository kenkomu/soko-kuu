import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Haptics and sound. Both persist in prefs. Haptics default on, sound off.
/// Uses only built-in platform feedback: no audio assets, no packages.
class Feel {
  static bool haptics = true;
  static bool sound = false;

  static void load(SharedPreferences p) {
    haptics = p.getBool('haptics') ?? true;
    sound = p.getBool('sound') ?? false;
  }

  static void select() {
    if (haptics) HapticFeedback.selectionClick();
  }

  static void light() {
    if (haptics) HapticFeedback.lightImpact();
  }

  /// One tick for a finished sale (plus a system click if sound is on).
  static void saleTick() {
    if (haptics) HapticFeedback.mediumImpact();
    if (sound) SystemSound.play(SystemSoundType.click);
  }
}
