import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final settingsProvider = ChangeNotifierProvider<SettingsController>(
    (_) => throw StateError('Settings not initialized'));

class SettingsController extends ChangeNotifier {
  SettingsController._(this._preferences, this._themeMode, this._locale);
  static const _themeKey = 'appearance.theme', _localeKey = 'appearance.locale';
  final SharedPreferences _preferences;
  ThemeMode _themeMode;
  Locale _locale;
  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_themeKey) ?? ThemeMode.system.name;
    final mode = ThemeMode.values
        .firstWhere((v) => v.name == name, orElse: () => ThemeMode.system);
    return SettingsController._(
        prefs, mode, Locale(prefs.getString(_localeKey) ?? 'fr'));
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    await _preferences.setString(_themeKey, value.name);
  }

  Future<void> setLocale(Locale value) async {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
    await _preferences.setString(_localeKey, value.languageCode);
  }
}
