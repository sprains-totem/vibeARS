import Foundation
import AVFoundation

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
            
            // Standard supported sample rates
            deviceMap["sampleRates"] = [16000, 44100, 48000]
            
            // Channel count supported
            let channels = port.channels?.count ?? 2
            deviceMap["channelCounts"] = [1, max(1, channels)]
            
            // Supported polar patterns if data sources exist
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
                print("[AudioDeviceManager] Successfully set preferred input to: \(targetPort.portName)")
                return true
            } catch {
                print("[AudioDeviceManager] Error setting preferred input: \(error)")
                return false
            }
        }
        return false
    }
    
    private func mapPortType(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "builtin_mic"
        case .headsetMic:
            return "wired_headset"
        case .bluetoothHFP:
            return "bluetooth_sco"
        case .bluetoothA2DP:
            return "bluetooth_a2dp"
        case .bluetoothLE:
            return "bluetooth_le"
        case .usbAudio:
            return "usb_audio"
        case .lineIn:
            return "aux_line"
        default:
            return "unknown"
        }
    }
}
