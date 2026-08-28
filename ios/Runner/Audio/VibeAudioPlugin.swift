import Foundation
import Flutter

public class VibeAudioPlugin: NSObject, FlutterPlugin, AudioEngineDelegate {
    private static let METHOD_CHANNEL = "com.vibears.app/audio_engine"
    private static let AUDIO_STREAM_CHANNEL = "com.vibears.app/audio_stream"
    private static let SLICE_STREAM_CHANNEL = "com.vibears.app/slice_stream"
    
    private var audioEventSink: FlutterEventSink?
    private var sliceEventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: METHOD_CHANNEL, binaryMessenger: registrar.messenger())
        let instance = VibeAudioPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        let audioEventChannel = FlutterEventChannel(name: AUDIO_STREAM_CHANNEL, binaryMessenger: registrar.messenger())
        audioEventChannel.setStreamHandler(instance.AudioStreamHandler(plugin: instance))
        
        let sliceEventChannel = FlutterEventChannel(name: SLICE_STREAM_CHANNEL, binaryMessenger: registrar.messenger())
        sliceEventChannel.setStreamHandler(instance.SliceStreamHandler(plugin: instance))
        
        AudioEngineManager.shared.delegate = instance
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAudioDevices":
            let devices = AudioDeviceManager.shared.getAvailableInputDevices()
            result(devices)
        case "startRecording":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments missing", details: nil))
                return
            }
            let sampleRate = args["sampleRate"] as? Double ?? 48000.0
            let channelCount = args["channelCount"] as? Int ?? 2
            let format = args["format"] as? String ?? "wav"
            let preferredDeviceId = args["preferredDeviceId"] as? String
            let slicerEnabled = args["slicerEnabled"] as? Bool ?? true
            let sliceDurationMinutes = args["sliceDurationMinutes"] as? Int ?? 5
            let outputDir = args["outputDir"] as? String ?? (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "")
            
            AudioEngineManager.shared.startRecording(
                sampleRate: sampleRate,
                channelCount: channelCount,
                format: format,
                preferredDeviceId: preferredDeviceId,
                slicerEnabled: slicerEnabled,
                sliceDurationMinutes: sliceDurationMinutes,
                outputDir: outputDir
            )
            result(true)
        case "pauseRecording":
            AudioEngineManager.shared.pauseRecording()
            result(true)
        case "resumeRecording":
            AudioEngineManager.shared.resumeRecording()
            result(true)
        case "stopRecording":
            AudioEngineManager.shared.stopRecording()
            result(true)
        case "requestIgnoreBatteryOptimizations":
            // iOS does not have Android's Doze battery whitelist concept; background audio mode handles this
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - AudioEngineDelegate
    func onAudioFrame(pcmData: Data, amplitude: Double, db: Double) {
        let flutterData = FlutterStandardTypedData(bytes: pcmData)
        audioEventSink?([
            "amplitude": amplitude,
            "db": db,
            "pcm": flutterData
        ])
    }
    
    func onSliceCompleted(sliceInfo: [String: Any]) {
        sliceEventSink?(sliceInfo)
    }
    
    func onError(errorMessage: String) {
        print("[VibeAudioPlugin] Error: \(errorMessage)")
    }
    
    // MARK: - Stream Handlers
    class AudioStreamHandler: NSObject, FlutterStreamHandler {
        private weak var plugin: VibeAudioPlugin?
        init(plugin: VibeAudioPlugin) { self.plugin = plugin }
        
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.audioEventSink = events
            return nil
        }
        
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.audioEventSink = nil
            return nil
        }
    }
    
    class SliceStreamHandler: NSObject, FlutterStreamHandler {
        private weak var plugin: VibeAudioPlugin?
        init(plugin: VibeAudioPlugin) { self.plugin = plugin }
        
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.sliceEventSink = events
            return nil
        }
        
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.sliceEventSink = nil
            return nil
        }
    }
}
