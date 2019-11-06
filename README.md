# Mobile Speech Bot

A template for a mobile speech bot, which relies on a bot implemented in Microsoft BotFramework 4. The speech part serves as a demo, which can use Tilde's speech services for speech recognition and synthesis.

## Getting started

The app is built using [Flutter](https://flutter.dev/). Please follow the Flutter [installation instructions](https://flutter.dev/docs/get-started/install) first, before trying to build this app.

The app is configured via `pubspec.yaml` and a `config.json` file, which has to be made from scratch. There is a `config_example.json`, which outlines all the available fields with placeholder values.

To create a new chatbot app based on this one:
1. clone the project
2. rename it in `pubspec.yaml`, and write some description
3. create a `config.json` with same fields as `config_example.json`

The only really required field is `bot_framework_secret`, which identifies the bot you want to use in your app and authorizes you to chat with it. No conversation will be possible without this specified.

Obtaining the access information for automatic speech recognition (ASR) and text-to-speech (TTS) can be done by contacting Tilde.

## License

Apache 2.0

## Acknowledgements

The development of this app has been supported by the European Regional Development Fund within the research project ”Neural Network Modelling for Inflected Natural Languages” No. 1.1.1.1/16/A/215