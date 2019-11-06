import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:pip_news_bot/settings/settings.dart';
import 'package:pip_news_bot/chat/chat_screen.dart';
import 'package:pip_news_bot/settings/settings_screen.dart';
import 'package:pip_news_bot/language_screen.dart';
import 'package:pip_news_bot/config_loader.dart';

void main() {
  // logging setup
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print("[${rec.loggerName} ${rec.level.name} ${rec.time}] ${rec.message}");
  });

  runApp(SpeechBotApp());
}

class SpeechBotApp extends StatefulWidget {
  @override
  _SpeechBotAppState createState() => _SpeechBotAppState();
}

class _SpeechBotAppState extends State<SpeechBotApp> {
  final Logger _log = Logger("SpeechBotApp");

  // global deps
  Settings settings;
  Map<String, dynamic> config;

  // session variables
  bool _languageChosen = false;
  bool _useEnglish = false;

  @override
  void initState() {
    super.initState();
    settings = Settings();
    settings.initSettings().then((_) {
      _log.fine("Settings have been initialized");
    });
    loadConfig("config.json").then((map) {
      config = map;
      _log.fine("Config has been loaded: $config");
    });
  }

  @override
  Widget build(BuildContext context) {
    // settings are provided globally...
    return ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        title: "News assistant",
        home: _languageChosen
            // we can only pass config by constructor here reliably
            // because of the delay introduced by presenting LanguageScreen first
            ? ChatScreen(config, useEnglish: _useEnglish)
            : LanguageScreen(
                onChoice: (bool english) {
                  this.setState(() {
                    this._useEnglish = english;
                    this._languageChosen = true;
                  });
                },
              ),
        routes: <String, WidgetBuilder>{
          SettingsScreen.routeName: (BuildContext context) => SettingsScreen(),
        },
      ),
    );
  }
}
