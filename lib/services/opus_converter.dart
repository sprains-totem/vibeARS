import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'log_collector.dart';

/// iOS Opus transcoding via the bundled libopusenc (Opus.xcframework vendored
/// and linked with -framework Opus). The same WAV -> .opus (OggOpus) pipeline
/// as MP3: record native WAV, then transcode after recording stops.
class OpusConverter {
  static bool get _isSupported => Platform.isIOS;

  static late final DynamicLibrary _lib = DynamicLibrary.process();

  // Native function typedefs (required by lookupFunction).
  typedef _StrErrNative = Pointer<Utf8> Function(Int32);
  typedef _StrErrDart = Pointer<Utf8> Function(int);
  typedef _CommentsCreateNative = Pointer<Void> Function();
  typedef _CommentsCreateDart = Pointer<Void> Function();
  typedef _CommentsDestroyNative = Void Function(Pointer<Void>);
  typedef _CommentsDestroyDart = void Function(Pointer<Void>);
  typedef _CreateFileNative = Pointer<Void> Function(
      Pointer<Utf8>, Pointer<Void>, Int32, Int32, Int32, Pointer<Int32>);
  typedef _CreateFileDart = Pointer<Void> Function(
      Pointer<Utf8>, Pointer<Void>, int, int, int, Pointer<Int32>);
  typedef _WriteNative = Int32 Function(Pointer<Void>, Pointer<Int16>, Int32);
  typedef _WriteDart = int Function(Pointer<Void>, Pointer<Int16>, int);
  typedef _DrainNative = Int32 Function(Pointer<Void>);
  typedef _DrainDart = int Function(Pointer<Void>);
  typedef _DestroyNative = Void Function(Pointer<Void>);
  typedef _DestroyDart = void Function(Pointer<Void>);

  static late final _StrErrDart _strerr =
      _lib.lookupFunction<_StrErrNative, _StrErrDart>('ope_strerror');
  static late final _CommentsCreateDart _commentsCreate =
      _lib.lookupFunction<_CommentsCreateNative, _CommentsCreateDart>('ope_comments_create');
  static late final _CommentsDestroyDart _commentsDestroy =
      _lib.lookupFunction<_CommentsDestroyNative, _CommentsDestroyDart>('ope_comments_destroy');
  static late final _CreateFileDart _encoderCreateFile =
      _lib.lookupFunction<_CreateFileNative, _CreateFileDart>('ope_encoder_create_file');
  static late final _WriteDart _encoderWrite =
      _lib.lookupFunction<_WriteNative, _WriteDart>('ope_encoder_write');
  static late final _DrainDart _encoderDrain =
      _lib.lookupFunction<_DrainNative, _DrainDart>('ope_encoder_drain');
  static late final _DestroyDart _encoderDestroy =
      _lib.lookupFunction<_DestroyNative, _DestroyDart>('ope_encoder_destroy');

  static bool get available {
    if (!_isSupported) return false;
    try {
      _commentsCreate();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> wavToOpus({
    required String inputPath,
    required int bitRate,
    required String outputDir,
  }) async {
    if (!_isSupported) return null;
    try {
      final wavBytes = await File(inputPath).readAsBytes();
      if (wavBytes.length < 44) return null;
      final byteData = ByteData.sublistView(wavBytes);
      if (byteData.getUint16(20, Endian.little) != 1) return null; // PCM only
      final channels = byteData.getUint16(22, Endian.little);
      if (channels != 1 && channels != 2) return null;
      final sampleRate = byteData.getUint32(24, Endian.little);

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
      if (dataOffset + 1 > wavBytes.length) return null;

      final pcm = Int16List.sublistView(byteData, dataOffset ~/ 2, dataEnd ~/ 2);
      final base = p.basenameWithoutExtension(inputPath);
      final outputPath = p.join(outputDir, '$base.opus');

      final comments = _commentsCreate();
      final err = calloc<Int32>();
      final pathC = outputPath.toNativeUtf8();
      final enc = _encoderCreateFile(pathC, comments, sampleRate, channels, 0, err);
      calloc.free(pathC);
      if (enc.address == 0) {
        final msg = err.value != 0 ? _errString(err.value) : 'unknown';
        LogCollector.instance.log('OpusConverter', '编码器创建失败: $msg');
        _commentsDestroy(comments);
        calloc.free(err);
        return null;
      }
      calloc.free(err);

      // Feed in 20ms frames.
      final frameSamples = sampleRate ~/ 50; // per channel
      final frameInts = frameSamples * channels;
      final buffer = malloc<Int16>(frameInts);
      var ok = true;
      for (var i = 0; i < pcm.length; i += frameInts) {
        final n = (i + frameInts <= pcm.length) ? frameInts : pcm.length - i;
        buffer.asTypedList(n).setAll(0, pcm.sublist(i, i + n));
        final rc = _encoderWrite(enc, buffer, (n ~/ channels).clamp(1, frameSamples));
        if (rc < 0 && rc != -1 /* OPE_*-ish negative */) {
          LogCollector.instance.log('OpusConverter', '写帧错误: $rc');
          ok = false;
          break;
        }
      }
      malloc.free(buffer);

      _encoderDrain(enc);
      _encoderDestroy(enc);
      _commentsDestroy(comments);

      if (!ok) return null;
      LogCollector.instance.log('OpusConverter', 'Opus 转码完成: $outputPath');
      return outputPath;
    } catch (e) {
      LogCollector.instance.log('OpusConverter', '转码异常: $e');
      return null;
    }
  }

  static String _errString(int code) {
    final cstr = _opeStrerror();
    if (cstr.address == 0) return 'error $code';
    return cstr.toDartString();
  }
}