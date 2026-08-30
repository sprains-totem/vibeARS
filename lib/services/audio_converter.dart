import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_lame/flutter_lame.dart';
import 'package:path/path.dart' as p;
import 'log_collector.dart';

/// MP3 post-recording transcoding using the bundled LAME encoder
/// (flutter_lame — a double-platform FFI plugin that compiles LAME for
/// Android and iOS). Recording stays native WAV; when the user selected
/// MP3, the finished WAV is transcoded and the intermediate removed.
class AudioConverter {
  /// Transcodes the given WAV file (16-bit PCM, standard RIFF layout) to MP3.
  /// Returns the new file path on success, null on failure.
  static Future<String?> wavToMp3({
    required String inputPath,
    required int bitRate,
    required String outputDir,
  }) async {
    try {
      final wavBytes = await File(inputPath).readAsBytes();
      if (wavBytes.length < 44) {
        LogCollector.instance.log('AudioConverter', 'WAV 文件过短无法解析: $inputPath');
        return null;
      }

      final byteData = ByteData.sublistView(wavBytes);
      final audioFormat = byteData.getUint16(20, Endian.little);
      if (audioFormat != 1) {
        LogCollector.instance.log('AudioConverter', '非 PCM WAV，跳过转码: $inputPath');
        return null;
      }
      final channels = byteData.getUint16(22, Endian.little);
      final sampleRate = byteData.getUint32(24, Endian.little);
      final bitsPerSample = byteData.getUint16(34, Endian.little);
      if (bitsPerSample != 16) {
        LogCollector.instance.log('AudioConverter', '仅支持 16-bit PCM 转码: $inputPath');
        return null;
      }

      // Locate the 'data' chunk.
      var dataOffset = 12;
      var dataEnd = wavBytes.length;
      while (dataOffset + 8 <= wavBytes.length) {
        final chunkId = String.fromCharCodes(wavBytes.sublist(dataOffset, dataOffset + 4));
        final size = byteData.getUint32(dataOffset + 4, Endian.little);
        if (chunkId == 'data') {
          dataOffset += 8;
          dataEnd = dataOffset + size;
          break;
        }
        dataOffset += 8 + size + (size.isOdd ? 1 : 0);
      }
      if (dataOffset + 1 > wavBytes.length) {
        LogCollector.instance.log('AudioConverter', 'WAV 缺少 data chunk: $inputPath');
        return null;
      }

      final pcmInt16 = Int16List.sublistView(byteData, dataOffset ~/ 2, dataEnd ~/ 2);
      final sampleCount = pcmInt16.length;

      final encoder = LameMp3Encoder(sampleRate, channels, bitRate);
      final mp3Bytes = <int>[];
      const block = 8192;
      for (var i = 0; i < sampleCount; i += block) {
        final end = (i + block < sampleCount) ? i + block : sampleCount;
        final chunk = Int16List.sublistView(pcmInt16, i, end);
        final encoded = encoder.encode(chunk);
        if (encoded != null) mp3Bytes.addAll(encoded);
      }
      final flush = encoder.flush();
      if (flush != null) mp3Bytes.addAll(flush);
      encoder.close();

      final base = p.basenameWithoutExtension(inputPath);
      final outputPath = p.join(outputDir, '$base.mp3');
      await File(outputPath).writeAsBytes(Uint8List.fromList(mp3Bytes), flush: true);
      LogCollector.instance.log(
        'AudioConverter',
        'MP3 转码完成: $outputPath (${(mp3Bytes.length / 1024).toStringAsFixed(0)} KB)',
      );
      return outputPath;
    } catch (e) {
      LogCollector.instance.log('AudioConverter', 'MP3 转码异常: $e');
      return null;
    }
  }
}