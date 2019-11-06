//
//  SpeechRecognitionPlugin.swift
//  Runner
//
//  Created by dev on 10/07/2019.
//  Copyright © 2019 The Chromium Authors. All rights reserved.
//

import Flutter
import UIKit
import Speech
import AVFoundation

@available(iOS 10.0, *)
public class SpeechRecognitionPlugin: NSObject, FlutterPlugin, SFSpeechRecognizerDelegate {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "speech_recognition", binaryMessenger: registrar.messenger())
        let instance = SpeechRecognitionPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    private var speechToText: SpeechToText?
    
    private var speechChannel: FlutterMethodChannel?
    
    private func initSpeechToText(endpoint: String,
                                  system: String,
                                  appId: String,
                                  appSecret: String) {
        let sttConf = STTConfiguration.init()!
        sttConf.appID = appId
        sttConf.appSecret = appSecret
        sttConf.groupId = "unused";
        sttConf.apiEndpoint = URL(string: endpoint + "/" + system)
        speechToText = SpeechToText.init(config: sttConf)
    }
    
    init(channel: FlutterMethodChannel) {
        speechChannel = channel
        super.init()
        // TODO does invoking this here make sense?
        channel.invokeMethod("speech.onSpeechAvailability", arguments: true)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        //result("iOS " + UIDevice.current.systemVersion)
        switch (call.method) {
        case "speech.activate":
            let arguments = call.arguments as! [String]
            let endpoint = arguments[0]
            let system = arguments[1]
            let appId = arguments[2]
            let appSecret = arguments[3]
            initSpeechToText(endpoint: endpoint, system: system, appId: appId, appSecret: appSecret)
            result(true)
            self.speechChannel?.invokeMethod("speech.onCurrentLocale", arguments: "\(Locale.current.identifier)")
        case "speech.listen":
            self.startRecognition(lang: call.arguments as! String, result: result)
        case "speech.cancel":
            self.cancelRecognition(result: result)
        case "speech.stop":
            self.stopRecognition(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // fixme start of AudioPlayerUtil copypasta
    private static let allowedPorts = [AVAudioSession.Port.headphones, AVAudioSession.Port.airPlay, AVAudioSession.Port.bluetoothA2DP,
                                       AVAudioSession.Port.bluetoothHFP, AVAudioSession.Port.bluetoothLE, AVAudioSession.Port.carAudio,
                                       AVAudioSession.Port.HDMI]
    
    private static func isOutputAllowed() -> Bool {
        return !AVAudioSession.sharedInstance()
            .currentRoute.outputs
            .filter {
                for p in allowedPorts {
                    if $0.portType == p {
                        return true
                    }
                }
                return false
            }
            .isEmpty
    }
    
    private static func configSession() {
        // make sure we always have both play and record
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(AVAudioSession.Category.playAndRecord,
                             mode: .default,
                             options: [AVAudioSession.CategoryOptions.allowAirPlay,
                                       AVAudioSession.CategoryOptions.allowBluetooth,
                                       AVAudioSession.CategoryOptions.allowBluetoothA2DP,
                                       AVAudioSession.CategoryOptions.defaultToSpeaker])
        } catch let error {
            print(error.localizedDescription)
        }
        if isOutputAllowed() {
            return
        }
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    private func startRecognition(lang: String, result: FlutterResult) {
        guard let stt: SpeechToText = speechToText else {
            print("Stt failed to init?!")
            result(false)
            return
        }
        SpeechRecognitionPlugin.configSession()
        stt.recognize({
            [weak self] (results: [AnyHashable: Any]?, error: Error?) -> Void in
            guard let slf = self else {
                return
            }
            if let err = error {
                stt.endRecognize()
                slf.speechChannel?.invokeMethod(
                    "speech.onError",
                    arguments: nil)
                // right now we just fail silently
            } else if let res = results {
                if stt.isFinalTranscript(results) {
                    slf.speechChannel?.invokeMethod(
                        "speech.onRecognitionComplete",
                        arguments: stt.getTranscript(res)
                    )
                } else {
                    slf.speechChannel?.invokeMethod(
                        "speech.onSpeech",
                        arguments: stt.getTranscript(res))
                }
            } else {
                print("no result and no error!")
                stt.endRecognize()
                slf.speechChannel?.invokeMethod(
                    "speech.onError",
                    arguments: nil)
            }
        })
        result(true)
        speechChannel!.invokeMethod("speech.onRecognitionStarted", arguments: nil)
    }
    
    private func cancelRecognition(result: FlutterResult?) {
        speechToText?.endRecognize()
        if let r = result {
            r(false)
        }
    }
    
    private func stopRecognition(result: FlutterResult) {
        speechToText?.endRecognize()
        result(false)
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVAudioSessionCategory(_ input: AVAudioSession.Category) -> String {
    return input.rawValue
}
