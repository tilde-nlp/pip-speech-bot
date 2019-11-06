import 'package:flutter/material.dart';
import 'package:pip_news_bot/chat/chat_models.dart';

typedef MessageCallback = void Function(ChatMessage message);

class ChatMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final TextStyle senderNameStyle = TextStyle(
      fontSize: 14.0, color: Colors.black, fontWeight: FontWeight.bold);
  final TextStyle senderFailedNameStyle =
      TextStyle(fontSize: 14.0, color: Colors.red, fontWeight: FontWeight.bold);
  final TextStyle messageFailedStyle = TextStyle(color: Colors.red);
  final MessageCallback onRetry;
  final MessageCallback onCancel;

  ChatMessageWidget({
    @required this.message,
    @required this.onRetry,
    @required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSent = message.status != MessageStatus.RECEIVED;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 10.0,
        vertical: 10.0,
      ),
      child: Row(
        children: isSent ? _buildSentLayout() : _buildReceivedLayout(),
      ),
    );
  }

  Widget _buildSentName() {
    switch (message.status) {
      case MessageStatus.FAILED:
        return Text(message.sender.role, style: senderFailedNameStyle);
      case MessageStatus.SENDING:
        final name = Text(message.sender.role, style: senderNameStyle);
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SizedBox(
                width: 16.0,
                height: 16.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                ),
              ),
            ),
            name,
          ],
        );
      default:
        return Text(message.sender.role, style: senderNameStyle);
    }
  }

  List<Widget> _buildSentLayout() {
    final Text text = message.status != MessageStatus.FAILED
        ? Text(message.message)
        : Text(message.message, style: messageFailedStyle);
    final msgContainer = Container(
      margin: const EdgeInsets.only(top: 5.0),
      child: text,
    );
    final List<Widget> widgets = message.status != MessageStatus.FAILED
        ? <Widget>[_buildSentName(), msgContainer]
        : <Widget>[
            _buildSentName(),
            msgContainer,
            FlatButton(
              onPressed: () => onRetry(message),
              child: Text(
                "Retry",
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              color: Colors.red,
            ),
            FlatButton(
              onPressed: () => onCancel(message),
              child: Text(
                "Cancel",
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              color: Colors.red,
            ),
          ];

    return <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: widgets,
        ),
      ),
    ];
  }

  List<Widget> _buildReceivedLayout() {
    return <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              // FIXME hack, because bot doesn't report its role explicitly!
              message.sender.role != null ? message.sender.role : "Bot",
              style: senderNameStyle,
            ),
            Container(
              margin: const EdgeInsets.only(
                top: 5.0,
              ),
              child: Text(message.message),
            ),
          ],
        ),
      ),
    ];
  }
}
