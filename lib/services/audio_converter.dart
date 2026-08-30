import 'dart:io';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:path/path.dart' as p;
import '../core/models/audio_config.dart';
import 'log_collector.dart';

/// Post-recording transcoding using the bundled, authoritative FFmpegKit
/// audio package (contains libmp3lame for MP3 and libopus for Opus).
///
/// Recording always captures to WAV natively (most reliable); when the user
/// selected MP3/Opus, the finished WAV is transcoded to the target format and
/// the intermediate WAV is removed — a short, retryable pipeline.
class AudioConverter {
  /// Best-effort availability check: the bundled library is loaded lazily by
  /// FFmpegKit on first execute; a failed command reports non-success below.
  static Future<bool> isAvailable() async => true;

  /// Converts [inputPath] (WAV) to the target [format] into [outputDir].
  /// Returns the new file path on success, null on failure.
  static Future<String?> convert({
    required String inputPath,
    required AudioFormatType format,
    required int bitRate,
    required String outputDir,
  }) async {
    try {
      final base = p.basenameWithoutExtension(inputPath);
      final ext = format.fileExtension;
      final outputPath = p.join(outputDir, '$base.$ext');
      final input = inputPath.replaceAll('"', '\\"');
      final output = outputPath.replaceAll('"', '\\"');

      final codec = switch (format) {
        AudioFormatType.mp3 => 'libmp3lame',
        AudioFormatType.opus => 'libopus',
        _ => 'copy', // WAV/AAC stay as-is (no transcode needed)
      };
      if (codec == 'copy') return inputPath;

      var kbps = bitRate ~/ 1000;
      if (kbps < 8) kbps = 8;
      if (kbps > 512) kbps = 512;

      final command = '-i "$input" -c:a $codec -b:a ${kbps}k -y "$output"';
      LogCollector.instance.log('AudioConverter', '转码命令: $command');

      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        LogCollector.instance.log('AudioConverter', '转码成功 -> $outputPath');
        return outputPath;
      }
      LogCollector.instance.log('AudioConverter', '转码失败 rc=$rc');
      return null;
    } catch (e) {
      LogCollector.instance.log('AudioConverter', '转码异常: $e');
      return null;
    }
  }
}