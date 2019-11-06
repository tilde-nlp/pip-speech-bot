import 'package:logging/logging.dart';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pip_news_bot/synthesis_cache.dart';

final Logger _log = Logger("SpeechSynthesis");

class _SynthesisRequest {
  final int id;
  final String text;

  _SynthesisRequest({this.id, this.text});
}

class SpeechSynthesis {
  final String endpoint;
  final String appId;
  final String appSecret;
  final String voice;
  bool _everythingSpecified = true;

  final AudioPlayer _player = AudioPlayer();
  final Dio _dio = Dio();
  final SynthesisCache _synthesisCache = SynthesisCache();
  final SplayTreeMap<int, _SynthesisRequest> _schedule = SplayTreeMap();
  int _lastProcessedId = -1;
  bool _requestInProgress = false;

  SpeechSynthesis(this.endpoint, this.appId, this.appSecret, this.voice) {
    if (endpoint == null) {
      _log.warning("No endpoint set for tts. Speech synthesis won't work.");
      _everythingSpecified = false;
    }
    if (appId == null) {
      _log.warning("No appId set for tts. Speech synthesis won't work.");
      _everythingSpecified = false;
    }
    if (appSecret == null) {
      _log.warning("No appSecret set for tts. Speech synthesis won't work.");
      _everythingSpecified = false;
    }
    if (voice == null) {
      _log.warning("No voice specified for tts. Speech synthesis won't work.");
      _everythingSpecified = false;
    }
  }

  /// requests remote synthesis, returns true if all ok, false otherwise
  Future<bool> _requestSynthesis(String text) async {
    if (!_everythingSpecified) {
      // some required config is missing for this component
      return false;
    }
    // auth stuff
    // timestamp has to be in seconds...
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final digestSrc = "$timestamp$appId$appSecret";
    final digest = sha1.convert(utf8.encode(digestSrc));
    // get temp dir path
    final Directory dir = await getTemporaryDirectory();
    final File file = File("${dir.path}/$timestamp.mp3");
    final fileExists = await file.exists();
    if (!fileExists) {
      await file.create();
    }
    // download speech file
    final response = await _dio.download(
      endpoint,
      file.path,
      queryParameters: {
        "text": text,
        "voice": voice,
        "pitch": 1.0,
        "tempo": 1.0,
        "timestamp": timestamp,
        "appID": appId,
        "appKey": digest.toString(),
      },
    );
    if (response.statusCode != 200) {
      _log.warning(
          "No audio could be fetched! statusCode: ${response.statusCode}, "
              "message: ${response.statusMessage}");
      return false;
    } else {
      _synthesisCache.add(text, file);
      return true;
    }
  }

  void scheduleForPlayback(String text, int id) async {
    if (text.length == 0) {
      return;
    }
    _log.fine("Scheduling tts for msg[id=$id] with text: $text");
    if (id > _lastProcessedId && !_schedule.containsKey(id)) {
      _log.fine("msg[id=$id] is new, requesting new synthesis!");
      _schedule[id] = _SynthesisRequest(id: id, text: text);
      _scheduleLoop();
    } else {
      _log.fine("msg[id=$id] is already scheduled or synthesized. ignoring!");
    }
  }

  Future<void> _scheduleLoop() async {
    if(!_requestInProgress) {
      while (_schedule.isNotEmpty) {
        _requestInProgress = true;
        final firstKey = _schedule.firstKey();
        final request = _schedule[firstKey];
        await play(request.text);
        _schedule.remove(firstKey);
        _lastProcessedId = firstKey;
      }
      _requestInProgress = false;
    }
  }

  Future<void> play(String text) async {
    _log.fine("Trying to play: $text");
    // lazy init cache, it's async, shouldn't be too bad...
    if (!_synthesisCache.isInitialized) {
      await _synthesisCache.init();
    }
    if (_synthesisCache.hasFileFor(text)) {
      _log.fine("Audio found in cache");
    } else {
      _log.fine("No cached audio available. Synthesizing...");
      final synthesisOk = await _requestSynthesis(text);
      if (synthesisOk) {
        _log.fine("Synthesis finished successfully.");
      } else {
        _log.warning("Synthesis failed.");
        return;
      }
    }
    _log.fine("playing back audio for: $text");
    await _player.play(_synthesisCache.getFor(text).path, isLocal: true);
    // wait until the state has changed from playing to smth else
    // that indicates that playback is done...
    await _player.onPlayerStateChanged.firstWhere((state) => state != AudioPlayerState.PLAYING);
    _log.fine("playback done");
  }

  void haltAllSpeech() async {
    _schedule.clear();
    stop();
  }

  void stop() async {
    await _player.stop();
  }

  void dispose() async {
    _player.dispose();
  }

  bool isPlaying() {
    return _player.state == AudioPlayerState.PLAYING;
  }
}
