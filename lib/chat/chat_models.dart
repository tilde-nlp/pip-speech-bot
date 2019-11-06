import 'package:flutter/widgets.dart';
import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:uuid/uuid.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger("ChatModels");

final _uuid = Uuid();

class ConversationInfo {
  final String conversationId;
  final String token;

  // TODO handle expiration
  final int expiresIn;
  final String streamUrl;
  final String referenceGrammarId;

  ConversationInfo({
    this.conversationId,
    this.token,
    this.expiresIn,
    this.streamUrl,
    this.referenceGrammarId,
  });

  factory ConversationInfo.fromJson(Map<String, dynamic> json) {
    return ConversationInfo(
      conversationId: json["conversationId"],
      token: json["token"],
      expiresIn: json["expires_in"],
      streamUrl: json["streamUrl"],
      referenceGrammarId: json["referenceGrammarId"],
    );
  }
}

class User {
  final String id;
  final String role;

  User({this.id, this.role});

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "role": role,
    };
  }

  factory User.newMobileUser() {
    return User(
      id: "mobile_${_uuid.v4()}",
      role: "user",
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json["id"],
      role: json["role"],
    );
  }
}

class ClientCapabilities {
  final bool requiresBotState = true;
  final bool supportsListening = true;
  final bool supportsTts = true;
  final String type = "ClientCapabilities";

  Map<String, dynamic> toJson() {
    return {
      "requiresBotState": requiresBotState,
      "supportsListening": supportsListening,
      "supportsTts": supportsTts,
      "type": type,
    };
  }
}

class Activity {
  final String id;
  final String type;
  final String channelId;
  final String text;
  final String timestamp;
  final String name;
  final User from;
  final List<dynamic> entities;
  final Map<String, String> value;

  Activity({
    this.type = "message",
    this.name,
    this.id,
    this.channelId = "directline",
    this.text,
    this.timestamp,
    this.from,
    this.entities,
    this.value,
  });

  Map<String, dynamic> toJson() {
    Map<String, dynamic> out = {
      "type": type,
      "channelId": channelId,
      "timestamp": timestamp,
    };
    if (name != null) {
      out["name"] = name;
    }
    if (text != null) {
      out["text"] = text;
    }
    if (User != null) {
      out["from"] = from;
    }
    if (entities != null) {
      out["entities"] = entities;
    }
    if (value != null) {
      out["value"] = value;
    }

    return out;
  }

  factory Activity.fromJson(Map<String, dynamic> json) {
    User user;
    if (json.containsKey("from")) {
      user = User.fromJson(json["from"]);
    } else {
      user = null;
    }
    return Activity(
      type: json["type"],
      id: json["id"],
      timestamp: json["timestamp"],
      channelId: json["channelId"],
      from: user,
      text: json["text"],
    );
  }
}

class Activities {
  final List<Activity> activities;
  final String watermark;

  Activities({this.activities, this.watermark});

  factory Activities.fromJson(Map<String, dynamic> json) {
    return Activities(
      activities: [for (var j in json["activities"]) Activity.fromJson(j)],
      watermark: json["watermark"],
    );
  }
}

enum MessageStatus {
  SENDING,
  SENT,
  RECEIVED,
  FAILED,
}

class ChatMessage {
  // simplified internal id to order messages by
  // derived from activity.id
  final int id;
  final MessageStatus status;
  final Activity activity;

  String get message => activity.text;

  // used to determine whether this message should be displayed to user
  // hack: sometimes bf returns empty messages, idk wtf is that about
  bool get containsText =>
      message != null &&
      message.length > 0 &&
      // ignore hacks as well!
      !message.startsWith("[HACK]");

  User get sender => activity.from;

  const ChatMessage({
    this.id,
    this.activity,
    this.status = MessageStatus.SENDING,
  });

  ChatMessage changeStatus(MessageStatus status) {
    return ChatMessage(
      id: this.id,
      activity: this.activity,
      status: status,
    );
  }

  static int idFromActivityId(String activityId) {
    final split = activityId.split("|");
    return int.parse(split[1]);
  }

  factory ChatMessage.fromReceivedActivity(Activity activity, User localUser) {
    var status = MessageStatus.RECEIVED;
    if (activity.from.id == localUser.id) {
      status = MessageStatus.SENT;
    }
    return ChatMessage(
      id: idFromActivityId(activity.id),
      activity: activity,
      status: status,
    );
  }
}

enum ChatStatus {
  OPENING,
  RECONNECTING,
  OPEN,
  FAILED,
}

// fixme dirty hacks from bot
enum HackAction {
  HANDLING_LONG_ACTION,
}

class ChatModel extends ChangeNotifier {
  // testing bot environment
//  static const _API_SECRET =
//      "wMd6U50Hjrk.WpePchTBWz7-aWEEclm_iNdUh4gSBAgSb_n94CBMnTE";
  // production bot environment
  // TODO make this configurable via secrets/config.json
//  static const _API_SECRET =
//      "JIXIR4_ivhs.lw_E0RBjJ345W34kVBdQPZf4FtSjxLh_xXyV6ZONKew";
  static const _API_URL_BASE = "https://directline.botframework.com";
  static const _API_URL_OPEN_CONVERSATION =
      "$_API_URL_BASE/v3/directline/conversations";
  String _sendActivityUrl;
  final String authSecret;

  // TODO use dio instead?
  final http.Client _httpClient = http.Client();
  final User user = User.newMobileUser();

  // internal, private state
  final List<ChatMessage> _messages = [];
  String _watermark;

  ChatStatus _status = ChatStatus.OPENING;

  // fixme dirty hacks from bot
  HackAction _pendingHackAction;

  bool get isSending {
    return _messages.isEmpty || _messages.last.status == MessageStatus.SENDING;
  }

  ConversationInfo _info;
  StreamSubscription _activitiesSubscription;

  // public views
  UnmodifiableListView<ChatMessage> get messages =>
      UnmodifiableListView(_messages);

  ChatStatus get status => _status;

  ConversationInfo get info => _info;

  final bool useEnglish;

  ChatModel(this.authSecret, {this.useEnglish}) {
    if (authSecret == null) {
      throw Exception("No authSecret to connect to BotFramework with!");
    }
    _log.info("UseEnglish: $useEnglish");
  }

  void _handleHackMessage(ChatMessage msg) {
    if (msg.message != null && msg.message.startsWith("[HACK]")) {
      // do things depending on the type of hack
      if (msg.message == "[HACK] HANDLING LONG ACTION") {
        _pendingHackAction = HackAction.HANDLING_LONG_ACTION;
        _log.fine("Acknowledged Hack: $_pendingHackAction");
      } else {
        _log.warning("Unknown hack message: ${msg.message}");
        _pendingHackAction = null;
      }
    }
  }

  Future<void> _subscribeToBotActivities(String streamUrl) async {
    var channel = IOWebSocketChannel.connect(streamUrl);
    _activitiesSubscription = channel.stream.listen(
      (dynamic data) {
        if (data.toString().length > 0) {
          _log.fine("activities received: $data");
          final activities = Activities.fromJson(json.decode(data));
          _watermark = activities.watermark;
          // parse messages, replace our SENDING local versions with
          // authoritative messages from the server
          for (final a in activities.activities) {
            final parsedMessage = ChatMessage.fromReceivedActivity(a, user);
            // remove sending messages, if we have the SENT versions
            if (parsedMessage.status == MessageStatus.SENT) {
              for (int i = _messages.length - 1; i >= 0; i--) {
                final m = _messages[i];
                if (m.status == MessageStatus.SENDING &&
                    m.message == parsedMessage.message) {
                  _messages.removeAt(i);
                  break;
                }
              }
            }
            // fixme handle dirty hacks
            _handleHackMessage(parsedMessage);
            // add response from server!
            _messages.add(parsedMessage);
          }
          // make sure messages are in order, sort them by their id
          // which follows conversation order
          _messages.sort((a, b) {
            return a.id - b.id;
          });
          notifyListeners();
        } else {
          _log.fine("activities received: keep-alive");
        }
      },
      onError: (error) {
        _log.warning("websocket error occurred: $error");
        _activitiesSubscription = null;
        _status = ChatStatus.FAILED;
        notifyListeners();
      },
      cancelOnError: true,
    );
  }

  Future<bool> _requestOptionsFromBot() async {
    final request = http.Request("OPTIONS", Uri.parse(_sendActivityUrl));
    var response = await _httpClient.send(request);
    _log.finer(
        "_requestOptionsFromBot response.status: ${response.statusCode}");
    // there's no body here
    return response.statusCode == 200;
  }

  Future<bool> _postActivity(Activity activity) async {
    final encodedBody = json.encode(activity);
    _log.fine("_postActivity requestBody: $encodedBody");
    final response = await _httpClient.post(
      _sendActivityUrl,
      headers: {
        "Authorization": "Bearer $authSecret",
        "Content-Type": "application/json",
      },
      body: json.encode(activity),
    );
    _log.fine("_postActivity response.statusCode: ${response.statusCode}");
    _log.fine("_postActivity response.body: ${response.body}");
    if (response.statusCode != 200) {
      _log.severe(
          "_postActivity failure. Status: ${response.statusCode}: ${response.body}");
      // fixme hack can override _postActivity failure, when long stuff happens...
      if (_pendingHackAction == HackAction.HANDLING_LONG_ACTION) {
        _log.fine(
            "$_pendingHackAction: ignoring failed post for long action starter");
        // this hack has second part
        return true;
      }
      return false;
    }
    return true;
  }

  Future<bool> _postGetStarted() async {
    final activity = Activity(
      type: "event",
      name: "webchat/join",
      value: {
        "locale": this.useEnglish ? "en-en" : "lv-lv",
      },
      from: user,
      entities: [ClientCapabilities()],
    );
    return await _postActivity(activity);
  }

  Future<ConversationInfo> _postOpenConversation() async {
    var response = await _httpClient.post(
      Uri.encodeFull(_API_URL_OPEN_CONVERSATION),
      headers: {"Authorization": "Bearer $authSecret"},
    );
    _log.fine("openConversation response.status: ${response.statusCode}");
    _log.fine("openConversation response: ${response.body}");
    if (response.statusCode == 200 || response.statusCode == 201) {
      return ConversationInfo.fromJson(json.decode(response.body));
    }
    _log.severe(
        "Could not open conversation. Status: ${response.statusCode}: ${response.body}");
    return null;
  }

  void _chatFailedToOpen() {
    _status = ChatStatus.FAILED;
    notifyListeners();
  }

  Future<void> openConversation() async {
    var conversationInfo = await _postOpenConversation();
    if (conversationInfo == null) {
      _chatFailedToOpen();
      return;
    }
    _info = conversationInfo;
    // compute send activity url that's based on conversationId
    _sendActivityUrl =
        "$_API_URL_BASE/v3/directline/conversations/${_info.conversationId}/activities";
    _log.fine("_sendActivityUrl: $_sendActivityUrl");
    // open websocket connection to bot to receive bot activities
    await _subscribeToBotActivities(_info.streamUrl);
    // tell bot to start first, we're very shy
    bool success = await _requestOptionsFromBot();
    if (!success) {
      _chatFailedToOpen();
      return;
    }
    success = await _postGetStarted();
    if (!success) {
      _chatFailedToOpen();
      return;
    }
    // everything's ok, chat's OPEN
    _status = ChatStatus.OPEN;
    notifyListeners();
  }

  void sendMessage(String text) async {
    // tentative order id
    // can be overriden by server, if the message texts are the same and status is SENDING
    int lastOrderId = -1;
    if (_messages.length > 0) {
      lastOrderId = _messages.last.id;
    }
    final tentativeId = lastOrderId + 1;
    final activity = Activity(
      text: text,
      from: user,
    );
    final ChatMessage msg = ChatMessage(
      id: tentativeId,
      activity: activity,
      status: MessageStatus.SENDING,
    );
    _messages.add(msg);
    notifyListeners();

    final bool success = await _postActivity(activity);
    // fixme hackerino
    if (success && _pendingHackAction == HackAction.HANDLING_LONG_ACTION) {
      _log.fine("$_pendingHackAction: setting message status to SENT");
      _pendingHackAction = null;
      // insert SENT at the right place
      final idx = _messages.indexOf(msg);
      _messages.insert(idx, msg.changeStatus(MessageStatus.SENT));
      _messages.remove(msg);
    }
    if (!success) {
      // mark message as failed
      _messages.remove(msg);
      _messages.add(msg.changeStatus(MessageStatus.FAILED));
    }

    // announce the new state to the world
    notifyListeners();
  }

  void retryMessage(ChatMessage msg) async {
    _log.fine("retrying $msg");
    _messages.remove(msg);
    final updatedMsg = msg.changeStatus(MessageStatus.SENDING);
    _messages.add(updatedMsg);
    notifyListeners();

    final bool success = await _postActivity(updatedMsg.activity);
    if (!success) {
      _messages.remove(updatedMsg);
      _messages.add(msg);
    }
    notifyListeners();
  }

  void cancelMessage(ChatMessage msg) async {
    _log.fine("cancelling $msg");
    _messages.remove(msg);
    notifyListeners();
  }

  void reconnect() async {
    _log.fine("reconnecting!");
    _status = ChatStatus.RECONNECTING;
    notifyListeners();

    // create reopening url
    final String conversationId = _info.conversationId;
    String reconnectUrl = "$_API_URL_OPEN_CONVERSATION/$conversationId";
    // use watermark, if we have one
    if (_watermark != null) {
      reconnectUrl = "$reconnectUrl?watermark=$_watermark";
    }

    var response = await _httpClient.get(Uri.encodeFull(reconnectUrl),
        headers: {"Authorization": "Bearer $authSecret"});
    if (response.statusCode == 200 || response.statusCode == 201) {
      _info = ConversationInfo.fromJson(json.decode(response.body));
      await _subscribeToBotActivities(_info.streamUrl);
      _status = ChatStatus.OPEN;
    } else {
      _status = ChatStatus.FAILED;
    }

    notifyListeners();
  }
}
