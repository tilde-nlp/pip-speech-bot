import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';

final Logger _log = Logger("Settings");

class Settings extends ChangeNotifier {
  SharedPreferences _prefs;

  bool _voiceResponse = true;
  bool get voiceResponse => _voiceResponse;

  bool _normalizeKeyboardInput = true;
  bool get normalizeKeyboardInput => _normalizeKeyboardInput;

  bool _normalizeASRInput = false;
  bool get normalizeASRInput => _normalizeASRInput;

  Settings();

  Future<void> initSettings() async {
    this._prefs = await SharedPreferences.getInstance();
    _voiceResponse = _prefs.getBool("VoiceResponse") ?? true;
    _normalizeKeyboardInput = _prefs.getBool("NormalizeKeyboardInput") ?? true;
    _normalizeASRInput = _prefs.getBool("NormalizeASRInput") ?? false;
    notifyListeners();
  }

  Future<void> setVoiceResponse(bool value) async {
    await _prefs.setBool("VoiceResponse", value);
    _voiceResponse = value;
    notifyListeners();
  }

  Future<void> setNormalizeKeyboardInput(bool value) async {
    await _prefs.setBool("NormalizeKeyboardInput", value);
    _normalizeKeyboardInput = value;
    notifyListeners();
  }

  Future<void> setNormalizeASRInput(bool value) async {
    await _prefs.setBool("NormalizeASRInput", value);
    _normalizeASRInput = value;
    notifyListeners();
  }

}