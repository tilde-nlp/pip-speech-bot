import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:pip_news_bot/settings/settings.dart';

final Logger _log = Logger("SettingsScreen");

class SettingsScreen extends StatefulWidget {
  static const String routeName = "/settings";

  @override
  SettingsState createState() {
    return SettingsState();
  }
}

typedef ModelValueChanged<T> = void Function(Settings model, T value);
typedef ValueFromModel = bool Function(Settings model);

class SettingsState extends State<SettingsScreen> {
  Widget buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget buildSettingsRow(
      {String text,
      ValueFromModel valueFromModel,
      ModelValueChanged<bool> onChanged}) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(text),
          ),
        ),
        Consumer<Settings>(
          builder: (ctx, model, _) => Switch(
            value: valueFromModel(model),
            onChanged: (bool value) => onChanged(model, value),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings"),
        backgroundColor: Colors.orangeAccent,
      ),
      body: Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            buildSectionTitle("Speech synthesis"),
            buildSettingsRow(
              text: "Respond using voice",
              valueFromModel: (Settings model) => model.voiceResponse,
              onChanged: (Settings model, bool value) =>
                  model.setVoiceResponse(value),
            ),
            Divider(height: 1.0),
            buildSectionTitle("Text normalization"),
            buildSettingsRow(
              text: "Normalize keyboard input",
              valueFromModel: (Settings model) => model.normalizeKeyboardInput,
              onChanged: (Settings model, bool value) =>
                  model.setNormalizeKeyboardInput(value),
            ),
            buildSettingsRow(
              text: "Normalize speech input",
              valueFromModel: (Settings model) => model.normalizeASRInput,
              onChanged: (Settings model, bool value) =>
                  model.setNormalizeASRInput(value),
            ),
            Divider(height: 1.0),
          ],
        ),
      ),
    );
  }
}
