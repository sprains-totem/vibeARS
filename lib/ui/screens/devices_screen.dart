import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_device.dart';
import '../../providers/app_state.dart';
import '../theme.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  IconData _getDeviceIcon(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.builtInMic:
        return Icons.phone_android;
      case AudioDeviceType.wiredHeadset:
        return Icons.headset_mic;
      case AudioDeviceType.bluetoothSco:
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothLe:
        return Icons.bluetooth_audio;
      case AudioDeviceType.usbAudio:
        return Icons.usb;
      case AudioDeviceType.auxLine:
        return Icons.cable;
      default:
        return Icons.mic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('上游麦克风与硬件探测'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新探测输入设备',
            onPressed: () => state.refreshDevices(),
          ),
        ],
      ),
      body: state.isLoadingDevices
          ? const Center(child: CircularProgressIndicator())
          : state.devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.mic_off, size: 64, color: VibeTheme.textSecondary),
                      const SizedBox(height: 16),
                      const Text('未探测到可用麦克风设备', style: TextStyle(color: VibeTheme.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => state.refreshDevices(),
                        child: const Text('重新扫描'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: state.devices.length,
                  itemBuilder: (context, index) {
                    final device = state.devices[index];
                    final isSelected = state.selectedDevice?.id == device.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected ? VibeTheme.primaryNeon : const Color(0xFF2C394B),
                          width: isSelected ? 2.0 : 1.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          state.selectDevice(device);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已选择输入源: ${device.name}'),
                              duration: const Duration(seconds: 2),
                              backgroundColor: VibeTheme.cardSurface,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? VibeTheme.primaryNeon.withOpacity(0.2)
                                          : VibeTheme.cardSurface,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _getDeviceIcon(device.type),
                                      color: isSelected ? VibeTheme.primaryNeon : VibeTheme.textSecondary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          device.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? VibeTheme.primaryNeon : VibeTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          device.type.displayName,
                                          style: const TextStyle(fontSize: 12, color: VibeTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Chip(
                                      label: Text('当前选用', style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
                                      backgroundColor: VibeTheme.primaryNeon,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              const Divider(height: 24, color: Color(0xFF2C394B)),
                              
                              // Hardware Capabilities Breakdown
                              const Text('支持的硬件输出能力：', style: TextStyle(fontSize: 12, color: VibeTheme.textSecondary)),
                              const SizedBox(height: 8),

                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  // Sample Rates
                                  ...device.sampleRates.map(
                                    (sr) => _CapabilityChip(
                                      label: '${sr / 1000} kHz',
                                      icon: Icons.graphic_eq,
                                      color: Colors.blueAccent,
                                    ),
                                  ),
                                  // Channels
                                  ...device.channelCounts.map(
                                    (ch) => _CapabilityChip(
                                      label: ch == 1 ? '单声道 (Mono)' : '双声道 (Stereo)',
                                      icon: Icons.surround_sound,
                                      color: Colors.purpleAccent,
                                    ),
                                  ),
                                  // Encodings
                                  ...device.encodings.map(
                                    (enc) => _CapabilityChip(
                                      label: enc,
                                      icon: Icons.code,
                                      color: Colors.tealAccent,
                                    ),
                                  ),
                                  // Polar Patterns (iOS)
                                  ...device.polarPatterns.map(
                                    (pat) => _CapabilityChip(
                                      label: pat,
                                      icon: Icons.radar,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _CapabilityChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
