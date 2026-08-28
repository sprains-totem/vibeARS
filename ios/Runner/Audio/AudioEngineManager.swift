import Foundation
import AVFoundation

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
    private var sliceDurationSeconds: Double = 300.0 // 5 minutes default
    private var outputDirectory: URL?
    
    // Slicer tracking
    private var currentSliceFileUrl: URL?
    private var currentSliceFileHandle: FileHandle?
    private var currentSlicePcmBytes: Int64 = 0
    private var currentSliceStartTime: Date?
    private var sliceSequence: Int = 1
    private var sessionId: String = UUID().uuidString
    
    private override init() {
        super.init()
        setupInterruptionNotifications()
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
        
        // Open the first slice file
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
            print("[AudioEngineManager] Audio engine started successfully")
        } catch {
            delegate?.onError(errorMessage: "Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    func pauseRecording() {
        isPaused = true
    }
    
    func resumeRecording() {
        isPaused = false
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        closeCurrentSlice()
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AudioEngineManager] Error deactivating session: \(error)")
        }
        print("[AudioEngineManager] Audio engine stopped")
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        
        // Calculate Amplitude and RMS
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
        
        // Convert Float32 buffer to 16-bit PCM bytes
        var pcmData = Data(capacity: totalSamples * 2)
        for frame in 0..<frameLength {
            for ch in 0..<channels {
                let sample = channelData[ch][frame]
                let clamped = max(-1.0, min(1.0, sample))
                let int16Sample = Int16(clamped * 32767.0)
                var littleEndian = int16Sample.littleEndian
                pcmData.append(UnsafeBufferPointer(start: &littleEndian, count: 1))
            }
        }
        
        // Dispatch PCM chunk to Flutter EventChannel
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.onAudioFrame(pcmData: pcmData, amplitude: normalizedAmp, db: db)
        }
        
        // Write to current slice file
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
        
        guard let handle = try? FileHandle(forWritingTo: fileUrl) else {
            print("[AudioEngineManager] Failed to create file handle for \(fileUrl.path)")
            return
        }
        
        if formatString == "wav" {
            // Write 44 byte header placeholder
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
        
        try? handle.synchronize()
        try? handle.close()
        
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
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Subchunk1Size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // AudioFormat = 1 (PCM)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // BitsPerSample = 16
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(totalAudioLen).littleEndian) { Array($0) })
        
        handle.seek(toFileOffset: 0)
        handle.write(header)
        try? handle.close()
    }
    
    private func setupInterruptionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(notification:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("[AudioEngineManager] Audio interruption began (e.g. phone call)")
            pauseRecording()
        case .ended:
            print("[AudioEngineManager] Audio interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resumeRecording()
                }
            }
        @unknown default:
            break
        }
    }
}
