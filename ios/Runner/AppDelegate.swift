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
        
        // Make sure the audio session is active so `availableInputs` is populated.
        if session.availableInputs == nil {
            try? session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
            try? session.setActive(true)
        }
        
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
    func onAudioFrame(pcmData: Data, amplitude: Double, db: Double, aacData: Data?)
    func onSliceCompleted(sliceInfo: [String: Any])
    func onError(errorMessage: String)
    func onLog(tag: String, message: String)
}

class AudioEngineManager: NSObject {
    static let shared = AudioEngineManager()
    weak var delegate: AudioEngineDelegate?

    /// Log to console AND forward to the in-app LogCollector.
    private func nl(_ tag: String, _ message: String) {
        print("[\(tag)] \(message)")
        delegate?.onLog(tag: tag, message: message)
    }
    
    private var audioEngine: AVAudioEngine?
    private var isRecording = false
    private var isPaused = false
    
    private var sampleRate: Double = 48000.0
    private var channelCount: AVAudioChannelCount = 2
    private var formatString: String = "wav"
    private var bitRate: Int = 128000
    private var slicerEnabled: Bool = true
    private var sliceDurationSeconds: Double = 300.0
    private var outputDirectory: URL?
    private var isWavOutput: Bool { formatString == "wav" }
    private var isM4aOutput: Bool { formatString == "m4a" || formatString == "aac" }
    
    private var currentSliceFileUrl: URL?
    private var currentSliceFileHandle: FileHandle?
    private var currentSliceAudioFile: AVAudioFile?
    private var currentSlicePcmBytes: Int64 = 0
    private var currentSliceStartTime: Date?
    private var sliceSequence: Int = 1
    private var sessionId: String = UUID().uuidString
    
    // Real-time uplink AAC/ADTS encoder (webSocketAac protocol).
    private var uplinkEnabled = false
    private var uplinkConverter: AVAudioConverter?
    private var uplinkCompressedBuffer: AVAudioCompressedBuffer?
    private var uplinkInputProvided = false
    
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
        bitRate: Int = 128000,
        uplinkAac: Bool = false,
        preferredDeviceId: String? = nil,
        slicerEnabled: Bool = true,
        sliceDurationMinutes: Int = 5,
        outputDir: String
    ) -> Bool {
        if isRecording { return true }
        
        self.sampleRate = sampleRate
        self.channelCount = AVAudioChannelCount(channelCount)
        self.formatString = format.lowercased()
        self.bitRate = bitRate
        self.uplinkEnabled = uplinkAac
        self.slicerEnabled = slicerEnabled
        self.sliceDurationSeconds = Double(sliceDurationMinutes * 60)
        self.outputDirectory = URL(fileURLWithPath: outputDir)
        self.sliceSequence = 1
        self.sessionId = UUID().uuidString
        nl("AudioEngineManager", "startRecording rate=\(sampleRate) ch=\(channelCount) fmt=\(format) uplinkAac=\(uplinkAac)")
        
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
                let ok = AudioDeviceManager.shared.setPreferredInput(uid: preferredUid)
                nl("AudioDeviceManager", "setPreferredInput(\(preferredUid)) -> \(ok)")
            }
        } catch {
            delegate?.onError(errorMessage: "Failed to configure AVAudioSession: \(error.localizedDescription)")
            nl("AudioEngineManager", "AVAudioSession configure failed: \(error)")
            return false
        }
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return false }
        
        let inputNode = engine.inputNode
        // Request a concrete PCM format on the tap so the engine converts the
        // hardware input to the user's sample rate / channel count. This is
        // required for WAV headers and AAC file settings to match the data.
        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else {
            delegate?.onError(errorMessage: "Failed to create target PCM format")
            return false
        }
        
        guard openNextSlice() else {
            audioEngine = nil
            return false
        }
        
        if uplinkEnabled {
            setupUplinkAac()
        }
        
        let bufferSize: AVAudioFrameCount = 2048
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: pcmFormat) { [weak self] (buffer, time) in
            guard let self = self, self.isRecording, !self.isPaused else { return }
            self.processAudioBuffer(buffer: buffer)
        }
        
        do {
            try engine.start()
            isRecording = true
            isPaused = false
            nl("AudioEngineManager", "AVAudioEngine started OK")
            return true
        } catch {
            // Clean up the slice file that was opened before engine start.
            closeCurrentSlice()
            audioEngine = nil
            delegate?.onError(errorMessage: "Failed to start AVAudioEngine: \(error.localizedDescription)")
            nl("AudioEngineManager", "AVAudioEngine start failed: \(error)")
            return false
        }
    }
    
    func pauseRecording() { isPaused = true }
    func resumeRecording() { isPaused = false }
    
    func stopRecording() {
        guard audioEngine != nil || isRecording else { return }
        isRecording = false
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        uplinkConverter = nil
        uplinkCompressedBuffer = nil
        
        closeCurrentSlice()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - Uplink AAC encoding (AVAudioConverter -> ADTS)
    
    private func setupUplinkAac() {
        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channelCount),
            AVEncoderBitRateKey: bitRate
        ]
        guard let outputFormat = AVAudioFormat(settings: settings) else {
            delegate?.onError(errorMessage: "Failed to create uplink AAC output format")
            return
        }
        guard let converter = AVAudioConverter(from: pcmFormat, to: outputFormat) else {
            delegate?.onError(errorMessage: "Failed to create uplink AAC converter")
            return
        }
        uplinkConverter = converter
        uplinkCompressedBuffer = AVAudioCompressedBuffer(
            format: converter.outputFormat,
            packetCapacity: 1024,
            maximumPacketSize: converter.maximumOutputPacketSize
        )
        uplinkInputProvided = false
    }
    
    private func encodeUplinkAac(from input: AVAudioPCMBuffer) -> Data? {
        guard let converter = uplinkConverter, let output = uplinkCompressedBuffer else { return nil }
        
        uplinkInputProvided = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if self.uplinkInputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            self.uplinkInputProvided = true
            outStatus.pointee = .haveData
            return input
        }
        
        guard status == .haveData, output.byteLength > 0 else { return nil }
        
        // AVAudioConverter emits raw AAC; wrap it in an ADTS header so the
        // server can decode a continuous stream.
        let payload = Data(bytes: output.data, count: Int(output.byteLength))
        var header = Data(count: 7)
        let frameLength = payload.count + 7
        let sampleRateIndex = Self.adtsSampleRateIndex(sampleRate)
        let channelConfig = min(Int(channelCount), 7)
        
        let profileBits = UInt8(2 & 0x03)
        let srIndexBits = UInt8(sampleRateIndex & 0x0F)
        let chTopBit = UInt8((channelConfig >> 2) & 0x01)
        let chLowBits = UInt8(channelConfig & 0x03)
        let frameHi = UInt8((frameLength >> 11) & 0x03)
        let frameMid = UInt8((frameLength >> 3) & 0xFF)
        let frameLo = UInt8(frameLength & 0x07)
        let b2 = UInt8((profileBits << 6) | (srIndexBits << 2) | chTopBit)
        let b3 = UInt8((chLowBits << 6) | frameHi)
        let b4 = frameMid
        let b5 = UInt8((frameLo << 5) | 0x1F)
        header[0] = 0xFF
        header[1] = 0xF1 // MPEG-4, no CRC
        header[2] = b2
        header[3] = b3
        header[4] = b4
        header[5] = b5
        header[6] = 0xFC
        
        var result = Data()
        result.append(header)
        result.append(payload)
        return result
    }
    
    private static func adtsSampleRateIndex(_ rate: Double) -> Int {
        switch Int(rate) {
        case 96000: return 0
        case 88200: return 1
        case 64000: return 2
        case 48000: return 3
        case 44100: return 4
        case 32000: return 5
        case 24000: return 6
        case 16000: return 8
        default: return 4 // 44100 fallback
        }
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
        
        // Encode an AAC/ADTS frame for the real-time uplink when enabled.
        let aacData = uplinkEnabled ? encodeUplinkAac(from: buffer) : nil
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.onAudioFrame(pcmData: pcmData, amplitude: normalizedAmp, db: db, aacData: aacData)
        }
        
        // Persist the frame: AAC/M4A goes through AVAudioFile (converts
        // float PCM -> AAC), WAV goes through a raw FileHandle.
        if isM4aOutput {
            if let audioFile = currentSliceAudioFile {
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    print("[AudioEngineManager] Error writing m4a: \(error)")
                    delegate?.onLog(tag: "AudioEngineManager", message: "Error writing m4a: \(error)")
                }
            }
        } else if let handle = currentSliceFileHandle {
            handle.write(pcmData)
        }
        
        // Track progress using PCM bytes regardless of container so the
        // time-based rollover threshold works for both formats.
        currentSlicePcmBytes += Int64(pcmData.count)
        
        let bytesPerSecond = Int64(sampleRate * Double(channelCount) * 2.0)
        let maxBytes = Int64(sliceDurationSeconds * Double(bytesPerSecond))
        
        if slicerEnabled && currentSlicePcmBytes >= maxBytes {
            closeCurrentSlice()
            if !openNextSlice() {
                delegate?.onError(errorMessage: "Failed to create next slice file, recording stopped")
                isRecording = false
            }
        }
    }
    
    private func openNextSlice() -> Bool {
        guard let dir = outputDirectory else {
            delegate?.onError(errorMessage: "Output directory is not configured")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            delegate?.onError(errorMessage: "Failed to create output directory: \(error.localizedDescription)")
            return false
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let ext = isM4aOutput ? "m4a" : "wav"
        let fileName = "vibe_slice_\(timestamp)_part\(sliceSequence).\(ext)"
        let fileUrl = dir.appendingPathComponent(fileName)
        
        if isM4aOutput {
            // Create an AVAudioFile that transcodes float PCM -> AAC (m4a).
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: Int(channelCount),
                AVEncoderBitRateKey: bitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            do {
                let audioFile = try AVAudioFile(forWriting: fileUrl, settings: settings)
                currentSliceAudioFile = audioFile
            } catch {
                delegate?.onError(errorMessage: "Failed to create m4a file: \(error.localizedDescription)")
                return false
            }
        } else {
            guard FileManager.default.createFile(atPath: fileUrl.path, contents: nil) else {
                delegate?.onError(errorMessage: "Failed to create slice file: \(fileUrl.path)")
                return false
            }
            guard let handle = try? FileHandle(forWritingTo: fileUrl) else {
                delegate?.onError(errorMessage: "Failed to open slice file for writing: \(fileUrl.path)")
                return false
            }
            let emptyHeader = Data(count: 44)
            handle.write(emptyHeader)
            currentSliceFileHandle = handle
        }
        
        currentSliceFileUrl = fileUrl
        currentSlicePcmBytes = 0
        currentSliceStartTime = Date()
        return true
    }
    
    private func closeCurrentSlice() {
        guard let fileUrl = currentSliceFileUrl else { return }
        
        // Close the m4a writer (finalizes the file) or flush the raw handle.
        if isM4aOutput {
            currentSliceAudioFile = nil // AVAudioFile finalizes on release
        } else {
            currentSliceFileHandle?.synchronizeFile()
            currentSliceFileHandle?.closeFile()
            writeWavHeader(fileUrl: fileUrl, totalAudioLen: currentSlicePcmBytes, sampleRate: Int(sampleRate), channels: Int(channelCount))
            currentSliceFileHandle = nil
        }
        
        let actualDurationMs = (currentSlicePcmBytes * 1000) / Int64(sampleRate * Double(channelCount) * 2.0)
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
        currentSliceAudioFile = nil
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
    private static let LOG_STREAM_CHANNEL = "com.vibears.app/log_stream"
    
    private var audioEventSink: FlutterEventSink?
    private var sliceEventSink: FlutterEventSink?
    private var logEventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: METHOD_CHANNEL, binaryMessenger: registrar.messenger())
        let instance = VibeAudioPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        let audioEventChannel = FlutterEventChannel(name: AUDIO_STREAM_CHANNEL, binaryMessenger: registrar.messenger())
        audioEventChannel.setStreamHandler(VibeAudioPlugin.AudioStreamHandler(plugin: instance))
        
        let sliceEventChannel = FlutterEventChannel(name: SLICE_STREAM_CHANNEL, binaryMessenger: registrar.messenger())
        sliceEventChannel.setStreamHandler(VibeAudioPlugin.SliceStreamHandler(plugin: instance))
        
        let logEventChannel = FlutterEventChannel(name: LOG_STREAM_CHANNEL, binaryMessenger: registrar.messenger())
        logEventChannel.setStreamHandler(VibeAudioPlugin.LogStreamHandler(plugin: instance))
        
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
            let bitRate = args["bitRate"] as? Int ?? 128000
            let uplinkAac = args["uplinkAac"] as? Bool ?? false
            let preferredDeviceId = args["preferredDeviceId"] as? String
            let slicerEnabled = args["slicerEnabled"] as? Bool ?? true
            let sliceDurationMinutes = args["sliceDurationMinutes"] as? Int ?? 5
            let outputDir = args["outputDir"] as? String ?? (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "")
            
            let started = AudioEngineManager.shared.startRecording(
                sampleRate: sampleRate,
                channelCount: channelCount,
                format: format,
                bitRate: bitRate,
                uplinkAac: uplinkAac,
                preferredDeviceId: preferredDeviceId,
                slicerEnabled: slicerEnabled,
                sliceDurationMinutes: sliceDurationMinutes,
                outputDir: outputDir
            )
            if started {
                result(true)
            } else {
                result(FlutterError(code: "RECORD_START_FAILED", message: "Failed to start audio recording", details: nil))
            }
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
        case "getDefaultStorageDirectory":
            let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
            let dir = (docs as NSString).appendingPathComponent("vibe_recordings")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            result(dir)
        case "getStoragePresets":
            let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
            let recDir = (docs as NSString).appendingPathComponent("vibe_recordings")
            let sharedDocs = (docs as NSString).appendingPathComponent("SharedRecordings")
            result([
                "app_sandbox": recDir,
                "public_documents": sharedDocs
            ])
        case "isManageStorageGranted":
            result(true)
        case "requestManageStoragePermission":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    func onAudioFrame(pcmData: Data, amplitude: Double, db: Double, aacData: Data?) {
        var event: [String: Any] = [
            "amplitude": amplitude,
            "db": db,
            "pcm": FlutterStandardTypedData(bytes: pcmData)
        ]
        if let aac = aacData {
            event["aac"] = FlutterStandardTypedData(bytes: aac)
        }
        audioEventSink?(event)
    }
    
    func onSliceCompleted(sliceInfo: [String: Any]) {
        sliceEventSink?(sliceInfo)
    }
    
    func onError(errorMessage: String) {
        print("[VibeAudioPlugin] Error: \(errorMessage)")
        logEventSink?(["tag": "VibeAudioPlugin", "message": "Error: \(errorMessage)"])
    }
    
    func onLog(tag: String, message: String) {
        logEventSink?(["tag": tag, "message": message])
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
    
    class LogStreamHandler: NSObject, FlutterStreamHandler {
        private weak var plugin: VibeAudioPlugin?
        init(plugin: VibeAudioPlugin) { self.plugin = plugin }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            plugin?.logEventSink = events
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            plugin?.logEventSink = nil
            return nil
        }
    }
}
