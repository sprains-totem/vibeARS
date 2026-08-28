enum SlicerUploadTarget {
  none,
  webdav,
  s3,
  both;

  String get displayName {
    switch (this) {
      case SlicerUploadTarget.none:
        return '仅本地存储 (不上传)';
      case SlicerUploadTarget.webdav:
        return 'WebDAV 远程网盘';
      case SlicerUploadTarget.s3:
        return 'S3 / 对象存储 (MinIO/R2/OSS)';
      case SlicerUploadTarget.both:
        return 'WebDAV 与 S3 双重备份';
    }
  }
}

enum SliceUploadStatus {
  idle,
  pending,
  uploading,
  success,
  failed;

  String get displayName {
    switch (this) {
      case SliceUploadStatus.idle:
        return '未开始';
      case SliceUploadStatus.pending:
        return '等待排队';
      case SliceUploadStatus.uploading:
        return '正在上传';
      case SliceUploadStatus.success:
        return '上传成功';
      case SliceUploadStatus.failed:
        return '上传失败';
    }
  }
}

class SlicerConfig {
  final bool enabled;
  final int intervalMinutes; // e.g. 5 minutes (or 1..60)
  final bool autoUpload;
  final bool keepLocalAfterUpload;
  final SlicerUploadTarget target;
  final String filePrefix;

  const SlicerConfig({
    this.enabled = true,
    this.intervalMinutes = 5,
    this.autoUpload = true,
    this.keepLocalAfterUpload = true,
    this.target = SlicerUploadTarget.webdav,
    this.filePrefix = 'vibe_rec',
  });

  factory SlicerConfig.fromJson(Map<String, dynamic> json) {
    return SlicerConfig(
      enabled: json['enabled'] as bool? ?? true,
      intervalMinutes: json['intervalMinutes'] as int? ?? 5,
      autoUpload: json['autoUpload'] as bool? ?? true,
      keepLocalAfterUpload: json['keepLocalAfterUpload'] as bool? ?? true,
      target: SlicerUploadTarget.values.firstWhere(
        (e) => e.name == json['target'],
        orElse: () => SlicerUploadTarget.webdav,
      ),
      filePrefix: json['filePrefix'] as String? ?? 'vibe_rec',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'intervalMinutes': intervalMinutes,
      'autoUpload': autoUpload,
      'keepLocalAfterUpload': keepLocalAfterUpload,
      'target': target.name,
      'filePrefix': filePrefix,
    };
  }

  SlicerConfig copyWith({
    bool? enabled,
    int? intervalMinutes,
    bool? autoUpload,
    bool? keepLocalAfterUpload,
    SlicerUploadTarget? target,
    String? filePrefix,
  }) {
    return SlicerConfig(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      autoUpload: autoUpload ?? this.autoUpload,
      keepLocalAfterUpload: keepLocalAfterUpload ?? this.keepLocalAfterUpload,
      target: target ?? this.target,
      filePrefix: filePrefix ?? this.filePrefix,
    );
  }
}

class AudioSliceItem {
  final String id;
  final int sequence;
  final String sessionId;
  final String localPath;
  final String fileName;
  final int durationMs;
  final int fileSizeBytes;
  final DateTime createdAt;
  SliceUploadStatus webdavStatus;
  SliceUploadStatus s3Status;
  double uploadProgress;
  String? errorMessage;
  int retryCount;

  AudioSliceItem({
    required this.id,
    required this.sequence,
    required this.sessionId,
    required this.localPath,
    required this.fileName,
    required this.durationMs,
    required this.fileSizeBytes,
    required this.createdAt,
    this.webdavStatus = SliceUploadStatus.idle,
    this.s3Status = SliceUploadStatus.idle,
    this.uploadProgress = 0.0,
    this.errorMessage,
    this.retryCount = 0,
  });

  factory AudioSliceItem.fromJson(Map<String, dynamic> json) {
    return AudioSliceItem(
      id: json['id'] as String,
      sequence: json['sequence'] as int? ?? 1,
      sessionId: json['sessionId'] as String? ?? '',
      localPath: json['localPath'] as String,
      fileName: json['fileName'] as String,
      durationMs: json['durationMs'] as int? ?? 0,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      webdavStatus: SliceUploadStatus.values.firstWhere(
        (e) => e.name == json['webdavStatus'],
        orElse: () => SliceUploadStatus.idle,
      ),
      s3Status: SliceUploadStatus.values.firstWhere(
        (e) => e.name == json['s3Status'],
        orElse: () => SliceUploadStatus.idle,
      ),
      uploadProgress: (json['uploadProgress'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['errorMessage'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sequence': sequence,
      'sessionId': sessionId,
      'localPath': localPath,
      'fileName': fileName,
      'durationMs': durationMs,
      'fileSizeBytes': fileSizeBytes,
      'createdAt': createdAt.toIso8601String(),
      'webdavStatus': webdavStatus.name,
      's3Status': s3Status.name,
      'uploadProgress': uploadProgress,
      'errorMessage': errorMessage,
      'retryCount': retryCount,
    };
  }
}
