import UIKit
import Flutter
//import SpeechRecognitionPlugin

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    SpeechRecognitionPlugin.register(with: registrar(forPlugin: "SpeechRecognition"))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
