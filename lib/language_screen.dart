import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger("LanguageScreen");

// language screen depends on settings, where we write our locale choice
// but we don't read or react to changes in settings in any way...

typedef ReadUserChoice = void Function(bool english);

class LanguageScreen extends StatelessWidget {

  final ReadUserChoice onChoice;

  LanguageScreen({this.onChoice});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FlatButton(
                  onPressed: () {
                    onChoice(false);
                  },
                  color: Colors.red,
                  textColor: Colors.white,
                  child: Text("Latviski"),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FlatButton(
                  onPressed: () {
                    onChoice(true);
                  },
                  color: Colors.red,
                  textColor: Colors.white,
                  child: Text("English"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
