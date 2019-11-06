import 'dart:io';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

final Logger _log = Logger("SynthesisCache");

class SynthesisCache {
  final Map<String, File> _cachedSpeech = Map();
  Database _db;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  SynthesisCache();

  Future<void> init() async {
    _db = await openDatabase(
      "tts_cache.db",
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute(
            "CREATE TABLE cache (id INTEGER PRIMARY KEY, text TEXT NOT NULL, file TEXT NOT NULL)");
      },
    );
    // fill up the map with the data from db
    List<Map> rows = await _db.rawQuery("SELECT * FROM cache");
    List<int> staleRowIds = List();
    for (var r in rows) {
      // validate that file exists, if it doesn't, mark the row as one to be removed
      File f = File(r["file"]);
      if (await f.exists()) {
        _cachedSpeech[r["text"]] = f;
      } else {
        staleRowIds.add(r["id"]);
      }
    }
    // remove all stale rows from db
    for (var id in staleRowIds) {
      await _db.rawDelete("DELETE FROM cache WHERE id = ?", [id]);
    }
    _isInitialized = true;
  }

  Future<void> add(String text, File file) async {
    _cachedSpeech[text] = file;
    await _db.execute(
        "INSERT INTO cache (text, file) VALUES(?, ?)", [text, file.path]);
  }

  bool hasFileFor(String text) {
    return _cachedSpeech.containsKey(text);
  }

  File getFor(String text) {
    return _cachedSpeech[text];
  }
}
