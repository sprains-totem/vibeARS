import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/slicer_config.dart';
import '../../core/models/storage_config.dart';
import 's3_storage_adapter.dart';
import 'webdav_storage_adapter.dart';

class UploadQueueManager extends ChangeNotifier {
  static final UploadQueueManager instance = UploadQueueManager._internal();
  UploadQueueManager._internal();

  final List<AudioSliceItem> _items = [];
  final Queue<AudioSliceItem> _pendingQueue = Queue<AudioSliceItem>();

  bool _isProcessing = false;
  WebDavConfig _webdavConfig = const WebDavConfig();
  S3Config _s3Config = const S3Config();
  SlicerConfig _slicerConfig = const SlicerConfig();

  List<AudioSliceItem> get items => List.unmodifiable(_items);
  bool get isProcessing => _isProcessing;

  int get pendingCount => _items.where((i) =>
      i.webdavStatus == SliceUploadStatus.pending ||
      i.s3Status == SliceUploadStatus.pending ||
      i.webdavStatus == SliceUploadStatus.uploading ||
      i.s3Status == SliceUploadStatus.uploading).length;

  int get successCount => _items.where((i) =>
      (_slicerConfig.target == SlicerUploadTarget.webdav && i.webdavStatus == SliceUploadStatus.success) ||
      (_slicerConfig.target == SlicerUploadTarget.s3 && i.s3Status == SliceUploadStatus.success) ||
      (_slicerConfig.target == SlicerUploadTarget.both && i.webdavStatus == SliceUploadStatus.success && i.s3Status == SliceUploadStatus.success)).length;

  void configure({
    required WebDavConfig webdavConfig,
    required S3Config s3Config,
    required SlicerConfig slicerConfig,
  }) {
    _webdavConfig = webdavConfig;
    _s3Config = s3Config;
    _slicerConfig = slicerConfig;
  }

  void enqueueSlice(AudioSliceItem slice) {
    if (_slicerConfig.target == SlicerUploadTarget.none || !_slicerConfig.autoUpload) {
      _items.insert(0, slice);
      notifyListeners();
      _saveHistory();
      return;
    }

    if (_slicerConfig.target == SlicerUploadTarget.webdav || _slicerConfig.target == SlicerUploadTarget.both) {
      slice.webdavStatus = SliceUploadStatus.pending;
    }
    if (_slicerConfig.target == SlicerUploadTarget.s3 || _slicerConfig.target == SlicerUploadTarget.both) {
      slice.s3Status = SliceUploadStatus.pending;
    }

    _items.insert(0, slice);
    _pendingQueue.add(slice);
    notifyListeners();
    _saveHistory();

    _processNext();
  }

  void retrySlice(String sliceId) {
    final items = _items.where((i) => i.id == sliceId).toList();
    if (items.isEmpty) return;
    final item = items.first;
    item.retryCount = 0;
    item.errorMessage = null;
    _markPending(item);
    if (!_pendingQueue.contains(item)) {
      _pendingQueue.add(item);
    }
    notifyListeners();
    _processNext();
  }

  void _markPending(AudioSliceItem item) {
    if (_slicerConfig.target == SlicerUploadTarget.webdav || _slicerConfig.target == SlicerUploadTarget.both) {
      if (item.webdavStatus == SliceUploadStatus.failed) {
        item.webdavStatus = SliceUploadStatus.pending;
      }
    }
    if (_slicerConfig.target == SlicerUploadTarget.s3 || _slicerConfig.target == SlicerUploadTarget.both) {
      if (item.s3Status == SliceUploadStatus.failed) {
        item.s3Status = SliceUploadStatus.pending;
      }
    }
  }

  void clearHistory() {
    _items.clear();
    _pendingQueue.clear();
    notifyListeners();
    _saveHistory();
  }

  /// Removes a single slice from the queue and history. If [deleteLocalFile]
  /// is true the local recording file is also deleted from disk.
  Future<bool> removeSlice(String sliceId, {bool deleteLocalFile = false}) async {
    final items = _items.where((i) => i.id == sliceId).toList();
    if (items.isEmpty) return false;
    final item = items.first;

    _items.remove(item);
    _pendingQueue.remove(item);
    notifyListeners();
    await _saveHistory();

    if (deleteLocalFile) {
      try {
        final file = File(item.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('[UploadQueueManager] Error deleting slice file: $e');
      }
    }
    return true;
  }

  Future<void> _processNext() async {
    if (_isProcessing) return;
    if (_pendingQueue.isEmpty) {
      _isProcessing = false;
      notifyListeners();
      return;
    }

    _isProcessing = true;
    notifyListeners();

    final item = _pendingQueue.removeFirst();
    final file = File(item.localPath);

    if (!await file.exists()) {
      item.errorMessage = 'Local file no longer exists: ${item.fileName}';
      item.webdavStatus = SliceUploadStatus.failed;
      item.s3Status = SliceUploadStatus.failed;
      _isProcessing = false;
      notifyListeners();
      _processNext();
      return;
    }

    // 1. WebDAV Upload
    if ((_slicerConfig.target == SlicerUploadTarget.webdav || _slicerConfig.target == SlicerUploadTarget.both) &&
        item.webdavStatus == SliceUploadStatus.pending) {
      if (_webdavConfig.isValid) {
        item.webdavStatus = SliceUploadStatus.uploading;
        notifyListeners();

        final webdavAdapter = WebDavStorageAdapter(_webdavConfig);
        final success = await webdavAdapter.uploadFile(
          file: file,
          remoteRelativePath: item.fileName,
          onProgress: (p) {
            item.uploadProgress = p;
            notifyListeners();
          },
        );

        if (success) {
          item.webdavStatus = SliceUploadStatus.success;
        } else {
          item.webdavStatus = SliceUploadStatus.failed;
          item.errorMessage = 'WebDAV upload failed';
        }
      } else {
        item.webdavStatus = SliceUploadStatus.failed;
        item.errorMessage = 'WebDAV server not configured';
      }
    }

    // 2. S3 Upload
    if ((_slicerConfig.target == SlicerUploadTarget.s3 || _slicerConfig.target == SlicerUploadTarget.both) &&
        item.s3Status == SliceUploadStatus.pending) {
      if (_s3Config.isValid) {
        item.s3Status = SliceUploadStatus.uploading;
        notifyListeners();

        final s3Adapter = S3StorageAdapter(_s3Config);
        final success = await s3Adapter.uploadFile(
          file: file,
          remoteRelativePath: item.fileName,
          onProgress: (p) {
            item.uploadProgress = p;
            notifyListeners();
          },
        );

        if (success) {
          item.s3Status = SliceUploadStatus.success;
        } else {
          item.s3Status = SliceUploadStatus.failed;
          item.errorMessage = (item.errorMessage != null ? '${item.errorMessage}; ' : '') + 'S3 upload failed';
        }
      } else {
        item.s3Status = SliceUploadStatus.failed;
        item.errorMessage = (item.errorMessage != null ? '${item.errorMessage}; ' : '') + 'S3 not configured';
      }
    }

    // 3. Cleanup local file if keepLocalAfterUpload is false
    final allDone = (item.webdavStatus == SliceUploadStatus.success || item.webdavStatus == SliceUploadStatus.idle) &&
        (item.s3Status == SliceUploadStatus.success || item.s3Status == SliceUploadStatus.idle);

    if (allDone && !_slicerConfig.keepLocalAfterUpload) {
      try {
        if (await file.exists()) {
          await file.delete();
          print('[UploadQueueManager] Deleted local copy after upload: ${file.path}');
        }
      } catch (e) {
        print('[UploadQueueManager] Error deleting local file: $e');
      }
    }

    _isProcessing = false;
    notifyListeners();
    _saveHistory();

    // Schedule automatic retry for failed items (max 3 attempts, exponential backoff).
    if ((item.webdavStatus == SliceUploadStatus.failed ||
            item.s3Status == SliceUploadStatus.failed) &&
        item.retryCount < 3) {
      item.retryCount++;
      final delaySeconds = 5 * (1 << (item.retryCount - 1)); // 5s, 10s, 20s
      Timer(Duration(seconds: delaySeconds), () {
        if (_items.contains(item) &&
            (item.webdavStatus == SliceUploadStatus.failed ||
                item.s3Status == SliceUploadStatus.failed)) {
          _markPending(item);
          if (!_pendingQueue.contains(item)) {
            _pendingQueue.add(item);
          }
          _processNext();
        }
      });
    }

    // Process remainder
    _processNext();
  }

  Future<void> loadHistory() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('vibears_upload_history');
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _items.clear();
        for (final entry in list) {
          _items.add(AudioSliceItem.fromJson(entry as Map<String, dynamic>));
        }
        notifyListeners();
      }
    } catch (e) {
      print('[UploadQueueManager] Failed to load history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_items.map((i) => i.toJson()).toList());
      await sp.setString('vibears_upload_history', encoded);
    } catch (e) {
      print('[UploadQueueManager] Failed to save history: $e');
    }
  }
}
