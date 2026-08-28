import UIKit
import Flutter
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    if let registrar = self.registrar(forPlugin: "VibeAudioPlugin") {
      VibeAudioPlugin.register(with: registrar)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - Audio Device Manager
class AudioDeviceManager {
    static let shared = AudioDeviceManager()
    private init() {}
    
    func getAvailableInputDevices() -> [[String: Any]] {
        let session = AVAudioSession.sharedInstance()
        var result: [[String: Any]] = []
        
        guard let inputs = session.availableInputs else {
            return result
        }
        
        let currentPreferred = session.preferredInput
        
        for port in inputs {
            var deviceMap: [String: Any] = [:]
            deviceMap["id"] = port.uid
            deviceMap["name"] = port.portName
            deviceMap["type"] = mapPortType(port.portType)
            deviceMap["isSelected"] = (port.uid == currentPreferred?.uid)
            deviceMap["sampleRates"] = [16000, 44100, 48000]
            
            let channels = port.channels?.count ?? 2
            deviceMap["channelCounts"] = [1, max(1, channels)]
            
            var polarPatterns: [String] = []
            if let dataSources = port.dataSources {
                for ds in dataSources {
                    if let patterns = ds.supportedPolarPatterns {
                        polarPatterns.append(contentsOf: patterns.map { $0.rawValue })
                    }
                }
            }
            deviceMap["polarPatterns"] = polarPatterns
            deviceMap["encodings"] = ["PCM_16BIT", "PCM_FLOAT"]
            
            result.append(deviceMap)
        }
        
        return result
    }
    
    func setPreferredInput(uid: String) -> Bool {
        let session = AVAudioSession.sharedInstance()
        guard let inputs = session.availableInputs else { return false }
        
        if let targetPort = inputs.first(where: { $0.uid == uid }) {
            do {
                try session.setPreferredInput(targetPort)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    private func mapPortType(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic: return "builtin_mic"
        case .headsetMic: return "wired_headset"
        case .bluetoothHFP: return "bluetooth_sco"
        case .bluetoothA2DP: return "bluetooth_a2dp"
        case .bluetoothLE: return "bluetooth_le"
        case .usbAudio: return "usb_audio"
        case .lineIn: return "aux_line"
        default: return "unknown"
        }
    }
}

// MARK: - Audio Engine Delegate & Manager
protocol AudioEngineDelegate: AnyObject {
    func onAudioFrame(pcmData: Data, amplitude: Double, db: Double)
    func onSliceCompleted(sliceInfo: [String: Any])
    func onError(errorMessage: String)
}

class AudioEngineManager: NSObject {
    static let shared = AudioEngineManager()
    weak var delegate: AudioEngineDelegate?
    
    private var audioEngine: AVAudioEngine?
    private var isRecording = false
    private var isPaused = false
    
    private var sampleRate: Double = 48000.0
    private var channelCount: AVAudioChannelCount = 2
    private var formatString: String = "wav"
    private var slicerEnabled: Bool = true
    private var sliceDurationSeconds: Double = 300.0
    private var outputDirectory: URL?
    
    private var currentSliceFileUrl: URL?
    private var currentSliceFileHandle: FileHandle?
    private var currentSlicePcmBytes: Int64 = 0
    private var currentSliceStartTime: Date?
    private var sliceSequence: Int = 1
    private var sessionId: String = UUID().uuidString
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(notification:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    func startRecording(
        sampleRate: Double = 48000.0,
        channelCount: Int = 2,
        format: String = "wav",
        preferredDeviceId: String? = nil,
        slicerEnabled: Bool = true,
        sliceDurationMinutes: Int = 5,
        outputDir: String
    ) {
        if isRecording { return }
        
        self.sampleRate = sampleRate
        self.channelCount = AVAudioChannelCount(channelCount)
        self.formatString = format.lowercased()
        self.slicerEnabled = slicerEnabled
        self.sliceDurationSeconds = Double(sliceDurationMinutes * 60)
        self.outputDirectory = URL(fileURLWithPath: outputDir)
        self.sliceSequence = 1
        self.sessionId = UUID().uuidString
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .mixWithOthers, .defaultToSpeaker]
            )
            try session.setPreferredSampleRate(sampleRate)
            try session.setActive(true)
            
            if let preferredUid = preferredDeviceId {
                _ = AudioDeviceManager.shared.setPreferredInput(uid: preferredUid)
            }
        } catch {
            delegate?.onError(errorMessage: "Failed to configure AVAudioSession: \(error.localizedDescription)")
            return
        }
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        openNextSlice()
        
        let bufferSize: AVAudioFrameCount = 2048
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self, self.isRecording, !self.isPaused else { return }
            self.processAudioBuffer(buffer: buffer)
        }
        
        do {
            try engine.start()
            isRecording = true
            isPaused = false
        } catch {
            delegate?.onError(errorMessage: "Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    func pauseRecording() { isPaused = true }
    func resumeRecording() { isPaused = false }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        closeCurrentSlice()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        
        var sumSquare: Float = 0.0
        var maxSample: Float = 0.0
        
        for frame in 0..<frameLength {
            for ch in 0..<channels {
                let sample = channelData[ch][frame]
                let absSample = abs(sample)
                if absSample > maxSample {
                    maxSample = absSample
                }
                sumSquare += sample * sample
            }
        }
        
        let totalSamples = frameLength * channels
        let rms = (totalSamples > 0) ? sqrt(sumSquare / Float(totalSamples)) : 0.0
        let normalizedAmp = Double(min(max(maxSample, 0.0), 1.0))
        let db = (rms > 0.00001) ? Double(min(max(20.0 * log10(rms) + 90.0, 0.0), 100.0)) : 0.0
        
        var pcmData = Data(capacity: totalSamples * 2)
        for frame in 0..<frameLength {
            for ch in 0..<channels {
                let sample = channelData[ch][frame]
                let clamped = max(-1.0, min(1.0, sample))
                let int16Sample = Int16(clamped * 32767.0)
                let littleEndian = int16Sample.littleEndian
                withUnsafeBytes(of: littleEndian) { pcmData.append(contentsOf: $0) }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.onAudioFrame(pcmData: pcmData, amplitude: normalizedAmp, db: db)
        }
        
        if let handle = currentSliceFileHandle {
            handle.write(pcmData)
            currentSlicePcmBytes += Int64(pcmData.count)
            
            let bytesPerSecond = Int64(sampleRate * Double(channelCount) * 2.0)
            let maxBytes = Int64(sliceDurationSeconds * Double(bytesPerSecond))
            
            if slicerEnabled && currentSlicePcmBytes >= maxBytes {
                closeCurrentSlice()
                openNextSlice()
            }
        }
    }
    
    private func openNextSlice() {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let ext = (formatString == "wav") ? "wav" : "pcm"
        let fileName = "vibe_slice_\(timestamp)_part\(sliceSequence).\(ext)"
        let fileUrl = dir.appendingPathComponent(fileName)
        
        FileManager.default.createFile(atPath: fileUrl.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: fileUrl) else { return }
        
        if formatString == "wav" {
            let emptyHeader = Data(count: 44)
            handle.write(emptyHeader)
        }
        
        currentSliceFileUrl = fileUrl
        currentSliceFileHandle = handle
        currentSlicePcmBytes = 0
        currentSliceStartTime = Date()
    }
    
    private func closeCurrentSlice() {
        guard let handle = currentSliceFileHandle, let fileUrl = currentSliceFileUrl else { return }
        
        handle.synchronizeFile()
        handle.closeFile()
        
        let actualDurationMs = (currentSlicePcmBytes * 1000) / Int64(sampleRate * Double(channelCount) * 2.0)
        if formatString == "wav" {
            writeWavHeader(fileUrl: fileUrl, totalAudioLen: currentSlicePcmBytes, sampleRate: Int(sampleRate), channels: Int(channelCount))
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.size] as? Int64) ?? currentSlicePcmBytes
        let isoFormatter = ISO8601DateFormatter()
        let sliceMap: [String: Any] = [
            "id": UUID().uuidString,
            "sequence": sliceSequence,
            "sessionId": sessionId,
            "localPath": fileUrl.path,
            "fileName": fileUrl.lastPathComponent,
            "durationMs": Int(actualDurationMs),
            "fileSizeBytes": Int(fileSize),
            "createdAt": isoFormatter.string(from: Date())
        ]
        
        sliceSequence += 1
        currentSliceFileHandle = nil
        currentSliceFileUrl = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.onSliceCompleted(sliceInfo: sliceMap)
        }
    }
    
    private func writeWavHeader(fileUrl: URL, totalAudioLen: Int64, sampleRate: Int, channels: Int) {
        guard let handle = try? FileHandle(forUpdating: fileUrl) else { return }
        let totalDataLen = totalAudioLen + 36
        let byteRate = Int64(sampleRate * channels * 2)
        let blockAlign = channels * 2
        
        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(totalDataLen).littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        header.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(totalAudioLen).littleEndian) { Array($0) })
        
        handle.seek(toFileOffset: 0)
        handle.write(header)
        handle.closeFile()
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        if type == .began {
            pauseRecording()
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                if AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    resumeRecording()
                }
            }
        }
    }
}

// MARK: - Flutter Native Plugin
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
        audioEventChannel.setStreamHandler(VibeAudioPlugin.AudioStreamHandler(plugin: instance))
        
        let sliceEventChannel = FlutterEventChannel(name: SLICE_STREAM_CHANNEL, binaryMessenger: registrar.messenger())
        sliceEventChannel.setStreamHandler(VibeAudioPlugin.SliceStreamHandler(plugin: instance))
        
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
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
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
