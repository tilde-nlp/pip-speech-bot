import 'dart:async';
import 'dart:ui';
import 'package:logging/logging.dart';
import 'package:flutter/services.dart';

final Logger _log = Logger("SpeechRecognition");

typedef void AvailabilityHandler(bool result);
typedef void StringResultHandler(String text);

/// the channel to control the speech recognition
class SpeechRecognition {
  // TODO make this configurable via secrets/config.json
  static const MethodChannel _channel =
      const MethodChannel('speech_recognition');

  static final SpeechRecognition _speech = new SpeechRecognition._internal();

  factory SpeechRecognition() => _speech;

  SpeechRecognition._internal() {
    _channel.setMethodCallHandler(_platformCallHandler);
  }

  AvailabilityHandler availabilityHandler;

  StringResultHandler currentLocaleHandler;
  StringResultHandler recognitionResultHandler;

  VoidCallback recognitionStartedHandler;

  StringResultHandler recognitionCompleteHandler;

  VoidCallback errorHandler;

  /// ask for speech recognizer permission beforehand!
  Future activate(
          String endpoint, String system, String appId, String appSecret) =>
      _channel.invokeMethod(
          "speech.activate", <String>[endpoint, system, appId, appSecret]);

  /// start listening
  Future listen({String locale}) =>
      _channel.invokeMethod("speech.listen", locale);

  /// cancel speech
  Future cancel() => _channel.invokeMethod("speech.cancel");

  /// stop listening
  Future stop() => _channel.invokeMethod("speech.stop");

  Future _platformCallHandler(MethodCall call) async {
    print("_platformCallHandler call ${call.method} ${call.arguments}");
    switch (call.method) {
      case "speech.onSpeechAvailability":
        availabilityHandler(call.arguments);
        break;
      case "speech.onCurrentLocale":
        currentLocaleHandler(call.arguments);
        break;
      case "speech.onSpeech":
        recognitionResultHandler(call.arguments);
        break;
      case "speech.onRecognitionStarted":
        recognitionStartedHandler();
        break;
      case "speech.onRecognitionComplete":
        recognitionCompleteHandler(call.arguments);
        break;
      case "speech.onError":
        errorHandler();
        break;
      default:
        _log.warning('Unknown method ${call.method} ');
    }
  }

  // define a method to handle availability / permission result
  void setAvailabilityHandler(AvailabilityHandler handler) =>
      availabilityHandler = handler;

  // define a method to handle recognition result
  void setPartialResultHandler(StringResultHandler handler) =>
      recognitionResultHandler = handler;

  // define a method to handle native call
  void setRecognitionStartedHandler(VoidCallback handler) =>
      recognitionStartedHandler = handler;

  // define a method to handle native call
  void setFinalResultHandler(StringResultHandler handler) =>
      recognitionCompleteHandler = handler;

  void setCurrentLocaleHandler(StringResultHandler handler) =>
      currentLocaleHandler = handler;

  void setErrorHandler(VoidCallback handler) => errorHandler = handler;
}

class AsrResult {
  final String text;
  final bool isFinal;

  AsrResult({this.text, this.isFinal});
}
