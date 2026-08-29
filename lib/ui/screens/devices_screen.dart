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
                              const SizedBox(height: 12),

                              // Selected output format + format picker
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? VibeTheme.primaryNeon.withOpacity(0.08)
                                      : VibeTheme.cardSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? VibeTheme.primaryNeon.withOpacity(0.5)
                                        : const Color(0xFF37474F),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.tune, size: 16, color: VibeTheme.primaryNeon),
                                        const SizedBox(width: 6),
                                        const Text(
                                          '输出格式 (采集参数)',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        const Spacer(),
                                        if (isSelected)
                                          Text(
                                            '${state.audioConfig.sampleRate / 1000} kHz · ${state.audioConfig.channelCount == 1 ? "单声道" : "双声道"}',
                                            style: const TextStyle(fontSize: 11, color: VibeTheme.primaryNeon, fontWeight: FontWeight.w600),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isSelected
                                          ? '录音时将使用上方参数采集。'
                                          : '点击选择该设备采集时使用的采样率与声道（仅在选中该设备后生效）。',
                                      style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 36),
                                        foregroundColor: VibeTheme.primaryNeon,
                                        side: const BorderSide(color: VibeTheme.primaryNeon),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.tune, size: 16),
                                      label: const Text('选择该设备输出格式', style: TextStyle(fontSize: 12)),
                                      onPressed: () => _showFormatPicker(context, state, device),
                                    ),
                                  ],
                                ),
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

  void _showFormatPicker(BuildContext context, AppState state, AudioInputDevice device) {
    // Local mutable selections inside the bottom sheet.
    var selectedSr = state.audioConfig.sampleRate;
    var selectedCh = state.audioConfig.channelCount;

    // Prefer values the device actually supports.
    if (!device.sampleRates.contains(selectedSr) && device.sampleRates.isNotEmpty) {
      selectedSr = device.sampleRates.first;
    }
    if (!device.channelCounts.contains(selectedCh) && device.channelCounts.isNotEmpty) {
      selectedCh = device.channelCounts.first;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161E2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择「${device.name}」的输出格式',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '选择后点击确认，该设置将在下一次录音时生效。',
                    style: const TextStyle(fontSize: 11, color: VibeTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),

                  const Text('采样率 (Sample Rate)：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: device.sampleRates.map((sr) {
                      final isSel = selectedSr == sr;
                      return ChoiceChip(
                        label: Text('${sr / 1000} kHz'),
                        selected: isSel,
                        selectedColor: VibeTheme.primaryNeon,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : Colors.white,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setSheetState(() => selectedSr = sr),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  const Text('声道数 (Channels)：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: device.channelCounts.map((ch) {
                      final isSel = selectedCh == ch;
                      return ChoiceChip(
                        label: Text(ch == 1 ? '单声道 (Mono)' : '双声道 (Stereo)'),
                        selected: isSel,
                        selectedColor: VibeTheme.primaryNeon,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : Colors.white,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setSheetState(() => selectedCh = ch),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  const Text('编码格式 (Encoding)：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: device.encodings.map((enc) {
                      return _CapabilityChip(
                        label: enc,
                        icon: Icons.code,
                        color: Colors.tealAccent,
                      );
                    }).toList(),
                  ),
                  const Text(
                    '原生采集统一为 16-bit PCM 编码；列表为该设备可用的硬件编码格式。',
                    style: TextStyle(fontSize: 10, color: VibeTheme.textSecondary),
                  ),
                  if (device.type == AudioDeviceType.bluetoothSco) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '蓝牙耳机 (HFP/SCO) 通话通道受协议限制，仅支持 16 kHz 单声道采集，将自动应用。',
                      style: TextStyle(fontSize: 10, color: VibeTheme.accentAmber),
                    ),
                  ],
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        state.selectDeviceFormat(device, sampleRate: selectedSr, channelCount: selectedCh);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已保存该设备的输出格式，下次录音生效'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('确认使用此格式'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
