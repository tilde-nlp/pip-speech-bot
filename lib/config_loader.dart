import 'package:logging/logging.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

final Logger _log = Logger("Config");

/// Attempts to load per-app config from the given path in the app assets
Future<Map<String, dynamic>> loadConfig(String path) async {
  try {
    final String data = await rootBundle.loadString(path);
    return json.decode(data);
  } catch (e) {
    _log.severe("Could not load config from \"$path\" due to: $e");
  }
  return {};
}