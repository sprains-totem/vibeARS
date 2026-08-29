import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../core/models/storage_config.dart';
import 'storage_adapter.dart';

class S3StorageAdapter implements StorageAdapter {
  final S3Config config;

  S3StorageAdapter(this.config);

  @override
  String get name => 'S3 (${config.bucketName} @ ${config.endpoint})';

  String _cleanEndpoint(String ep) {
    var e = ep.trim();
    if (e.startsWith('https://')) e = e.substring(8);
    if (e.startsWith('http://')) e = e.substring(7);
    if (e.endsWith('/')) e = e.substring(0, e.length - 1);
    return e;
  }

  String _sha256Hex(List<int> data) {
    return sha256.convert(data).toString();
  }

  List<int> _hmacSha256(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).bytes;
  }

  String _hmacSha256Hex(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).toString();
  }

  List<int> _getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
    final kSecret = utf8.encode('AWS4$key');
    final kDate = _hmacSha256(kSecret, utf8.encode(dateStamp));
    final kRegion = _hmacSha256(kDate, utf8.encode(regionName));
    final kService = _hmacSha256(kRegion, utf8.encode(serviceName));
    final kSigning = _hmacSha256(kService, utf8.encode('aws4_request'));
    return kSigning;
  }

  /// AWS SigV4 requires the canonical query string to be URI-encoded and
  /// sorted by key. Dart's `Uri` keeps raw query, so we normalize here.
  String _canonicalQuery(String rawQuery) {
    if (rawQuery.isEmpty) return '';
    final params = <String, String>{};
    for (final pair in rawQuery.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx == -1) {
        params[Uri.encodeComponent(pair)] = '';
      } else {
        final k = Uri.encodeComponent(pair.substring(0, idx));
        final v = Uri.encodeComponent(pair.substring(idx + 1));
        params[k] = v;
      }
    }
    final keys = params.keys.toList()..sort();
    return keys.map((k) => '$k=${params[k]}').join('&');
  }

  Map<String, String> _buildSigV4Headers({
    required String method,
    required Uri uri,
    required String payloadHash,
    required DateTime now,
  }) {
    final amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now.toUtc());
    final dateStamp = DateFormat('yyyyMMdd').format(now.toUtc());

    final host = uri.port == 80 || uri.port == 443 || uri.port == 0
        ? uri.host
        : '${uri.host}:${uri.port}';

    final canonicalUri = uri.path.isEmpty ? '/' : uri.path;
    final canonicalQuery = _canonicalQuery(uri.query);

    final canonicalHeaders = 'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = '$method\n$canonicalUri\n$canonicalQuery\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
    final hashedCanonicalRequest = _sha256Hex(utf8.encode(canonicalRequest));

    final credentialScope = '$dateStamp/${config.region}/s3/aws4_request';
    final stringToSign = 'AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n$hashedCanonicalRequest';

    final signingKey = _getSignatureKey(config.secretKey, dateStamp, config.region, 's3');
    final signature = _hmacSha256Hex(signingKey, utf8.encode(stringToSign));

    final authorizationHeader =
        'AWS4-HMAC-SHA256 Credential=${config.accessKey}/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    return {
      'host': host,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization': authorizationHeader,
    };
  }

  /// Builds the base object URI. The [queryParameters] (if any) are appended
  /// as an encoded query string so the SigV4 canonical query is correct.
  Uri _buildObjectUri(String objectKey, [Map<String, String>? queryParameters]) {
    final endpoint = _cleanEndpoint(config.endpoint);
    final scheme = config.useSsl ? 'https' : 'http';
    final cleanKey = objectKey.startsWith('/') ? objectKey.substring(1) : objectKey;

    final String base;
    if (config.usePathStyle) {
      // Path-style: https://endpoint/bucket/key (MinIO standard)
      base = '$scheme://$endpoint/${config.bucketName}/$cleanKey';
    } else {
      // Virtual-hosted-style: https://bucket.endpoint/key (AWS standard)
      base = '$scheme://${config.bucketName}.$endpoint/$cleanKey';
    }

    final uri = Uri.parse(base);
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: queryParameters);
  }

  @override
  Future<bool> testConnection() async {
    final client = http.Client();
    try {
      final uri = _buildObjectUri('');
      final now = DateTime.now();
      const emptyPayloadHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      final headers = _buildSigV4Headers(
        method: 'HEAD',
        uri: uri,
        payloadHash: emptyPayloadHash,
        now: now,
      );

      final response = await client.head(uri, headers: headers).timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 403;
    } catch (e) {
      print('[S3] Connection test failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> uploadFile({
    required File file,
    required String remoteRelativePath,
    void Function(double progress)? onProgress,
  }) async {
    if (!await file.exists()) {
      print('[S3] File not found: ${file.path}');
      return false;
    }

    final client = http.Client();
    try {
      final prefix = config.remotePrefix.endsWith('/') ? config.remotePrefix : '${config.remotePrefix}/';
      final fullObjectKey = '$prefix$remoteRelativePath';
      final uri = _buildObjectUri(fullObjectKey);

      final fileBytes = await file.readAsBytes();
      final payloadHash = _sha256Hex(fileBytes);
      final now = DateTime.now();

      final headers = _buildSigV4Headers(
        method: 'PUT',
        uri: uri,
        payloadHash: payloadHash,
        now: now,
      );

      headers['Content-Type'] = _getContentType(file.path);
      headers['Content-Length'] = fileBytes.length.toString();

      final request = http.StreamedRequest('PUT', uri);
      request.headers.addAll(headers);

      final totalBytes = fileBytes.length;
      var bytesSent = 0;
      const chunkSize = 64 * 1024; // 64KB chunk

      var offset = 0;
      while (offset < totalBytes) {
        final end = (offset + chunkSize < totalBytes) ? offset + chunkSize : totalBytes;
        final chunk = fileBytes.sublist(offset, end);
        request.sink.add(chunk);
        bytesSent += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(bytesSent / totalBytes);
        }
        offset = end;
      }
      request.sink.close();

      final response = await client.send(request).timeout(const Duration(minutes: 5));
      final success = response.statusCode == 200 || response.statusCode == 201;

      if (success) {
        print('[S3] File uploaded successfully to $fullObjectKey');
        onProgress?.call(1.0);
        return true;
      } else {
        final body = await response.stream.bytesToString();
        print('[S3] Upload failed with status ${response.statusCode}: $body');
        return false;
      }
    } catch (e) {
      print('[S3] Upload exception: $e');
      return false;
    } finally {
      client.close();
    }
  }

  @override
  Future<List<String>> listRemoteFiles(String remoteDir) async {
    final client = http.Client();
    try {
      final uri = _buildObjectUri('', {
        'list-type': '2',
        'prefix': remoteDir,
        'max-keys': '1000',
      });
      const emptyHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final headers = _buildSigV4Headers(
        method: 'GET',
        uri: uri,
        payloadHash: emptyHash,
        now: DateTime.now(),
      );

      final res = await client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final keyRegex = RegExp(r'<Key>([^<]+)<\/Key>');
        return keyRegex.allMatches(res.body).map((m) => m.group(1) ?? '').toList();
      }
      return [];
    } catch (e) {
      print('[S3] List files exception: $e');
      return [];
    } finally {
      client.close();
    }
  }

  String _getContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) return 'audio/opus';
    return 'application/octet-stream';
  }
}
