import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import "package:provider/provider.dart";
import 'package:permission/permission.dart';
import 'package:pip_news_bot/chat/chat_message_widget.dart';
import 'package:pip_news_bot/chat/chat_models.dart';
import 'package:pip_news_bot/settings/settings_screen.dart';
import 'package:pip_news_bot/speech_recognition.dart';
import 'package:pip_news_bot/speech_synthesis.dart';
import 'package:pip_news_bot/text_normalizer.dart';
import 'package:pip_news_bot/settings/settings.dart';

final Logger _log = Logger("ChatScreen");

class ChatScreen extends StatefulWidget {
  final bool useEnglish;
  final Map<String, dynamic> config;

  ChatScreen(this.config, {this.useEnglish});

  @override
  ChatState createState() {
    return ChatState(config, useEnglish: useEnglish);
  }
}

typedef void AsrFinishedCallback();

class ChatState extends State<ChatScreen> {
  final TextNormalizer _textNormalizer; // = TextNormalizer();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textEditingController = TextEditingController();
  bool _isComposingMessage = false;

  final SpeechSynthesis _tts;
  final SpeechRecognition _asr = SpeechRecognition();
  bool _asrIsListening = false;
  String _asrLocale;
  AsrFinishedCallback _asrFinishedCallback;

  final Map<String, dynamic> config;
  final bool useEnglish;
  final ChatModel chatModel; // = ChatModel(useEnglish: useEnglish);

  ChatState(this.config, {this.useEnglish})
      : chatModel =
            ChatModel(config["bot_framework_secret"], useEnglish: useEnglish),
        // TODO graceful fallback, when loading from config fails?
        _textNormalizer = TextNormalizer(config["normalizer_endpoint"]),
        _tts = SpeechSynthesis(config["tts_endpoint"], config["tts_app_id"],
            config["tts_app_secret"], config["tts_voice"]);

  @override
  void initState() {
    super.initState();
    _asr.setCurrentLocaleHandler((String locale) => setState(() {
          _asrLocale = locale;
        }));
    _asr.setRecognitionStartedHandler(() => setState(() {
          _asrIsListening = true;
        }));
    _asr.setPartialResultHandler((String result) => setState(() {
          if (_asrIsListening) {
            _textEditingController.text = result;
          }
        }));
    _asr.setFinalResultHandler((String result) => setState(() {
          if (_asrIsListening) {
            _textEditingController.text = result;
          }
          // we only process up to one utterance here!
          _asrIsListening = false;
          _asr.cancel();
          // TODO is this a good idea to do this inside setState()?
          if (_asrFinishedCallback != null) {
            _asrFinishedCallback();
          }
        }));
    _asr.setErrorHandler(() => setState(() {
          _asrIsListening = false;
        }));
    _asr
        .activate(config["asr_endpoint"], config["asr_system"],
            config["asr_app_id"], config["asr_app_secret"])
        .then((dynamic available) => setState(() {
              // TODO anything else?
              _log.fine("asr is available: $available");
            }));
    // init chat
    chatModel.openConversation();
    chatModel.addListener(() {
      // fixme does chatstatus matter for tts stuff?
//      if (chatModel.status == ChatStatus.OPEN) {
      _readBotResponsesInVoice(chatModel);
//      }
    });
  }

  Widget _buildChatList(BuildContext context, ChatModel model) {
    // fixme this also scrolls stuff to the end, when user is typing message for some reason?
    //  probably because of the state stuff!
    SchedulerBinding.instance.addPostFrameCallback((_) =>
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut));
    return ListView(
      controller: _scrollController,
      children: [
        for (var m in model.messages)
          if (m.containsText)
            ChatMessageWidget(
              message: m,
              onRetry: (msg) => model.retryMessage(msg),
              onCancel: (msg) => model.cancelMessage(msg),
            )
      ],
    );
  }

  void _sendMessage(ChatModel model, String text, bool fromAsr) async {
    // if normalization enabled for this mode, then do it
    // fixme since normalization is a network call, this can potentially hang for a while...
    final settings = Provider.of<Settings>(context);
    if (!useEnglish &&
        ((fromAsr && settings.normalizeASRInput) ||
            (!fromAsr && settings.normalizeKeyboardInput))) {
      text = await _textNormalizer.normalize(text);
    }

    _textEditingController.clear();
    // ghetto hack that hides keyboard, taken from here: https://stackoverflow.com/a/51741121
    SystemChannels.textInput.invokeMethod("TextInput.hide");

    setState(() {
      _isComposingMessage = false;
    });
    model.sendMessage(text);
  }

  Widget _buildSendButton(ChatModel model) {
    final onPressed = _isComposingMessage && !model.isSending
        ? () => _sendMessage(model, _textEditingController.text, false)
        : null;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return CupertinoButton(
        child: Text("Send"),
        onPressed: onPressed,
      );
    } else {
      return IconButton(
        icon: Icon(Icons.send),
        onPressed: onPressed,
      );
    }
  }

  // fixme these methods are copy-pasta from asr test screen
  // fixme can we DRY it up somehow? add higher-level methods to ASR plugin?

  bool _isAudioRecordingAllowed(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.allow:
      case PermissionStatus.always:
      case PermissionStatus.whenInUse:
        return true;
      default:
        return false;
    }
  }

  bool _canAskForPermissions(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.deny:
      case PermissionStatus.notDecided:
        return true;
      default:
        return false;
    }
  }

  Future<bool> _checkPermissionsAndroid() async {
    List<Permissions> micPermission =
        await Permission.getPermissionsStatus([PermissionName.Microphone]);
    if (micPermission.length == 0 ||
        !_isAudioRecordingAllowed(micPermission.first.permissionStatus)) {
      if (_canAskForPermissions(micPermission.first.permissionStatus)) {
        List<Permissions> micPermission =
            await Permission.requestPermissions([PermissionName.Microphone]);
        if (micPermission.length > 0) {
          if (!_isAudioRecordingAllowed(micPermission.first.permissionStatus)) {
            // permission was not given after all
            return false;
          }
        }
      } else {
        // no permission status returned... prob some error, anyway, no permission...
        return false;
      }
    }
    return true;
  }

  Future<bool> _checkPermissionsiOS() async {
    PermissionStatus micPermission =
        await Permission.getSinglePermissionStatus(PermissionName.Microphone);
    if (!_isAudioRecordingAllowed(micPermission)) {
      if (_canAskForPermissions(micPermission)) {
        micPermission =
            await Permission.requestSinglePermission(PermissionName.Microphone);
        if (!_isAudioRecordingAllowed(micPermission)) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  Future<void> _showNoPermissionAlert() async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: Text("No Microphone permission"),
          content: Text(
              "App does not have permission to use Microphone. Go to Settings and manually grant the permission."),
          actions: <Widget>[
            FlatButton(
              child: Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            FlatButton(
              child: Text("Settings"),
              onPressed: () {
                Permission.openSettings();
                Navigator.of(context).pop();
              },
            )
          ],
        );
      },
    );
  }

  Future<void> _startSpeechRecognition(ChatModel model) async {
    bool permissionGranted = false;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      permissionGranted = await _checkPermissionsiOS();
      if (!permissionGranted) {
        _log.fine("audio permissions not allowed!");
        _showNoPermissionAlert();
        return;
      }
    } else {
      permissionGranted = await _checkPermissionsAndroid();
      if (!permissionGranted) {
        _log.fine("audio permissions not allowed!");
        _showNoPermissionAlert();
        return;
      }
    }
    _log.fine("audio permissions allowed");

    _asrFinishedCallback = () {
      _sendMessage(model, _textEditingController.text, true);
    };
    _asr.listen(locale: _asrLocale).then((result) {
      _log.fine("result: $result");
    });
  }

  void _stopSpeechRecognition(ChatModel model) async {
    _asr.cancel();
    setState(() {
      if (_textEditingController.text.length > 0) {
        _isComposingMessage = true;
      }
    });
  }

  Widget _buildAsrButton(ChatModel model) {
    _asrFinishedCallback = () {
      _sendMessage(model, _textEditingController.text, false);
    };
    // disable asr button if we're sending stuff currently...
    // that way user can't pile up multiple messages
    final onPressed = !model.isSending
        ? () {
            if (_asrIsListening) {
              _stopSpeechRecognition(model);
            } else {
              _startSpeechRecognition(model);
            }
          }
        : null;
    return SizedBox(
      width: 64,
      height: 64,
      child: FloatingActionButton(
        child: Icon(
          _asrIsListening ? Icons.mic_off : Icons.mic,
          color: _asrIsListening ? Colors.red : Colors.white,
          size: 48,
        ),
        backgroundColor: _asrIsListening ? Colors.white : Colors.red,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildTextComposer(ChatModel model) {
    final List<Widget> columnChildren = [];
    // only add asr button for latvian interface
    if (!useEnglish) {
      columnChildren.add(
        Container(
          child: _buildAsrButton(model),
          margin: const EdgeInsets.only(top: 16.0, bottom: 16.0),
        ),
      );
    }
    columnChildren.add(
      Row(
        children: <Widget>[
          Flexible(
            child: TextField(
              controller: _textEditingController,
              enabled: !_asrIsListening,
              onChanged: (String messageText) {
                setState(() {
                  _isComposingMessage = messageText.length > 0;
                });
              },
              onSubmitted: (String text) => _sendMessage(model, text, false),
              decoration: InputDecoration.collapsed(hintText: "Send a message"),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            child: _buildSendButton(model),
          ),
        ],
      ),
    );
    return IconTheme(
      data: IconThemeData(
        color: _isComposingMessage
            ? Theme.of(context).accentColor
            : Theme.of(context).disabledColor,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          children: columnChildren,
        ),
      ),
    );
  }

  int _lastSynthesizedMessageIdx = 0;
  int _lastSeenMessageCount = 0;

  void _readBotResponsesInVoice(ChatModel model) {
    final settings = Provider.of<Settings>(context);
    final messages = model.messages;
    _log.fine("read bot responses in voice, messages.length=${messages.length},"
        " _lastSeenMessageCount=$_lastSeenMessageCount, "
        "_lastSynthesizedMessageIdx=$_lastSynthesizedMessageIdx");
    if (_lastSeenMessageCount != messages.length) {
      _log.fine("trying to synth stuff!");
      int i = _lastSynthesizedMessageIdx;
      _log.fine("starting at $i");
      for (; i < messages.length; ++i) {
        _log.fine("loop pos at $i");
        final msg = messages[i];
        if (msg.status == MessageStatus.RECEIVED && msg.containsText) {
          if (settings.voiceResponse && !useEnglish) {
            _tts.scheduleForPlayback(msg.message, msg.id);
          }
        }
      }
      _lastSynthesizedMessageIdx = i;
      // check last message, if it's SENDING or SENT, then halt synthesis
      final lastMsg = messages.last;
      if (lastMsg.status == MessageStatus.SENDING ||
          lastMsg.status == MessageStatus.SENT) {
        _log.fine("user sending message, halting all speech");
        _tts.haltAllSpeech();
      }
    }
    _lastSeenMessageCount = messages.length;
  }

  Widget _buildChatStatusControls(BuildContext ctx, ChatModel model) {
    if (model.status == ChatStatus.FAILED) {
      return Container(
        color: Colors.red,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Text(
                  "Chat connection lost",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            FlatButton(
              onPressed: () => model.reconnect(),
              textColor: Colors.white,
              child: Text("Reconnect"),
            ),
          ],
        ),
      );
    }
    // if status ok, return an invisible widget p much
    return Container(
      width: 0.0,
      height: 0.0,
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    final List<Widget> out = [];
    // FIXME asr tests
//          IconButton(
//            icon: Icon(Icons.mic),
//            onPressed: () {
//              Navigator.of(context).pushNamed(AsrTestScreen.routeName);
//            },
//          ),
    if (!useEnglish) {
      out.add(
        IconButton(
          icon: Icon(Icons.settings),
          onPressed: () {
            Navigator.of(context).pushNamed(SettingsScreen.routeName);
          },
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // TODO better colors?
    // TODO add chat reconnection buttons at the bottom that respond to ChatModel
    return Scaffold(
      appBar: AppBar(
        title: Text("PIP1 Chat screen"),
        actions: _buildAppBarActions(context),
      ),
      body: Container(
        child: ChangeNotifierProvider.value(
          value: chatModel,
          child: Column(
            children: <Widget>[
              Consumer<ChatModel>(
                builder: (ctx, model, _) =>
                    Flexible(child: _buildChatList(context, model)),
              ),
              Consumer<ChatModel>(
                builder: (ctx, model, _) =>
                    _buildChatStatusControls(ctx, model),
              ),
              Divider(height: 1.0),
              Container(
                decoration: BoxDecoration(color: Theme.of(context).cardColor),
                child: Consumer<ChatModel>(
                  builder: (ctx, model, _) => _buildTextComposer(model),
                ),
              ),
            ],
          ),
        ),
        // TODO dfq is dis?
        decoration: Theme.of(context).platform == TargetPlatform.iOS
            ? BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[200])))
            : null,
      ),
    );
  }
}
