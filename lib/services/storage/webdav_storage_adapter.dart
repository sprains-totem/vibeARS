import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/models/storage_config.dart';
import 'storage_adapter.dart';

class WebDavStorageAdapter implements StorageAdapter {
  final WebDavConfig config;

  WebDavStorageAdapter(this.config);

  @override
  String get name => 'WebDAV (${config.serverUrl})';

  String get _authHeader {
    final credentials = '${config.username}:${config.password}';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  String _normalizeUrl(String base, String path) {
    var b = base.trim();
    if (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    var p = path.trim();
    if (!p.startsWith('/')) {
      p = '/$p';
    }
    return '$b$p';
  }

  @override
  Future<bool> testConnection() async {
    try {
      final url = Uri.parse(_normalizeUrl(config.serverUrl, config.remoteDir));
      final request = http.Request('PROPFIND', url);
      request.headers['Authorization'] = _authHeader;
      request.headers['Depth'] = '0';
      request.headers['Content-Type'] = 'application/xml; charset=utf-8';

      final client = http.Client();
      final response = await client.send(request).timeout(const Duration(seconds: 10));

      if (response.statusCode == 207 || response.statusCode == 200) {
        return true;
      }

      // If remote dir does not exist (404), try testing base server URL
      if (response.statusCode == 404) {
        final baseUrl = Uri.parse(config.serverUrl);
        final baseReq = http.Request('PROPFIND', baseUrl);
        baseReq.headers['Authorization'] = _authHeader;
        baseReq.headers['Depth'] = '0';
        final baseRes = await client.send(baseReq).timeout(const Duration(seconds: 10));
        return baseRes.statusCode == 207 || baseRes.statusCode == 200;
      }

      return false;
    } catch (e) {
      print('[WebDAV] Connection test failed: $e');
      return false;
    }
  }

  Future<bool> _ensureDirectoryExists(String dirPath) async {
    final parts = dirPath.split('/').where((p) => p.isNotEmpty).toList();
    var currentPath = '';

    for (final part in parts) {
      currentPath += '/$part';
      final url = Uri.parse(_normalizeUrl(config.serverUrl, currentPath));

      try {
        // Check if directory exists
        final checkReq = http.Request('PROPFIND', url);
        checkReq.headers['Authorization'] = _authHeader;
        checkReq.headers['Depth'] = '0';
        final checkRes = await http.Client().send(checkReq).timeout(const Duration(seconds: 5));

        if (checkRes.statusCode == 200 || checkRes.statusCode == 207) {
          continue;
        }

        // Create directory with MKCOL
        final mkcolReq = http.Request('MKCOL', url);
        mkcolReq.headers['Authorization'] = _authHeader;
        final mkcolRes = await http.Client().send(mkcolReq).timeout(const Duration(seconds: 8));

        if (mkcolRes.statusCode != 201 && mkcolRes.statusCode != 405) {
          print('[WebDAV] Failed to create folder: $currentPath, status: ${mkcolRes.statusCode}');
        }
      } catch (e) {
        print('[WebDAV] Error ensuring directory $currentPath: $e');
      }
    }
    return true;
  }

  @override
  Future<bool> uploadFile({
    required File file,
    required String remoteRelativePath,
    void Function(double progress)? onProgress,
  }) async {
    if (!await file.exists()) {
      print('[WebDAV] File does not exist: ${file.path}');
      return false;
    }

    try {
      // Ensure target remote directory exists
      final remoteDir = config.remoteDir.endsWith('/') ? config.remoteDir : '${config.remoteDir}/';
      await _ensureDirectoryExists(remoteDir);

      final fullRemotePath = _normalizeUrl(config.serverUrl, '$remoteDir$remoteRelativePath');
      final targetUri = Uri.parse(fullRemotePath);

      final totalBytes = await file.length();
      var bytesSent = 0;

      final request = http.StreamedRequest('PUT', targetUri);
      request.headers['Authorization'] = _authHeader;
      request.headers['Content-Length'] = totalBytes.toString();
      request.headers['Content-Type'] = 'application/octet-stream';

      final fileStream = file.openRead();
      final streamSubscription = fileStream.listen((chunk) {
        request.sink.add(chunk);
        bytesSent += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(bytesSent / totalBytes);
        }
      }, onDone: () {
        request.sink.close();
      }, onError: (e) {
        request.sink.addError(e);
      }, cancelOnError: true);

      final client = http.Client();
      final response = await client.send(request).timeout(const Duration(minutes: 5));
      await streamSubscription.asFuture();

      final success = response.statusCode == 201 || response.statusCode == 200 || response.statusCode == 204;
      if (success) {
        print('[WebDAV] Upload succeeded: $fullRemotePath');
        onProgress?.call(1.0);
        return true;
      } else {
        final body = await response.stream.bytesToString();
        print('[WebDAV] Upload failed with status ${response.statusCode}: $body');
        return false;
      }
    } catch (e) {
      print('[WebDAV] Upload exception: $e');
      return false;
    }
  }

  @override
  Future<List<String>> listRemoteFiles(String remoteDir) async {
    try {
      final url = Uri.parse(_normalizeUrl(config.serverUrl, remoteDir));
      final request = http.Request('PROPFIND', url);
      request.headers['Authorization'] = _authHeader;
      request.headers['Depth'] = '1';

      final response = await http.Client().send(request);
      if (response.statusCode == 207) {
        final body = await response.stream.bytesToString();
        // Extract hrefs from XML
        final hrefRegex = RegExp(r'<[^:]*:?href[^>]*>([^<]+)<\/[^:]*:?href>');
        final matches = hrefRegex.allMatches(body);
        return matches.map((m) => m.group(1) ?? '').where((s) => s.isNotEmpty).toList();
      }
      return [];
    } catch (e) {
      print('[WebDAV] Error listing files: $e');
      return [];
    }
  }
}
