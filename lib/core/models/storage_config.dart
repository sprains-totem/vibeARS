class WebDavConfig {
  final bool enabled;
  final String serverUrl; // e.g. https://dav.jianguoyun.com/dav/
  final String username;
  final String password;
  final String remoteDir; // e.g. /vibeARS/recordings
  final bool allowSelfSignedCert;

  const WebDavConfig({
    this.enabled = false,
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remoteDir = '/vibeARS/recordings',
    this.allowSelfSignedCert = false,
  });

  factory WebDavConfig.fromJson(Map<String, dynamic> json) {
    return WebDavConfig(
      enabled: json['enabled'] as bool? ?? false,
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remoteDir: json['remoteDir'] as String? ?? '/vibeARS/recordings',
      allowSelfSignedCert: json['allowSelfSignedCert'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'remoteDir': remoteDir,
      'allowSelfSignedCert': allowSelfSignedCert,
    };
  }

  WebDavConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? remoteDir,
    bool? allowSelfSignedCert,
  }) {
    return WebDavConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteDir: remoteDir ?? this.remoteDir,
      allowSelfSignedCert: allowSelfSignedCert ?? this.allowSelfSignedCert,
    );
  }

  bool get isValid => serverUrl.trim().isNotEmpty;
}

class S3Config {
  final bool enabled;
  final String endpoint; // e.g. s3.amazonaws.com or play.min.io or xxx.r2.cloudflarestorage.com
  final String region; // e.g. us-east-1, auto, cn-north-1
  final String bucketName;
  final String accessKey;
  final String secretKey;
  final String remotePrefix; // e.g. vibe_slices/
  final bool usePathStyle; // true for MinIO/Local, false for AWS S3
  final bool useSsl;

  const S3Config({
    this.enabled = false,
    this.endpoint = '',
    this.region = 'us-east-1',
    this.bucketName = '',
    this.accessKey = '',
    this.secretKey = '',
    this.remotePrefix = 'recordings/',
    this.usePathStyle = false,
    this.useSsl = true,
  });

  factory S3Config.fromJson(Map<String, dynamic> json) {
    return S3Config(
      enabled: json['enabled'] as bool? ?? false,
      endpoint: json['endpoint'] as String? ?? '',
      region: json['region'] as String? ?? 'us-east-1',
      bucketName: json['bucketName'] as String? ?? '',
      accessKey: json['accessKey'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
      remotePrefix: json['remotePrefix'] as String? ?? 'recordings/',
      usePathStyle: json['usePathStyle'] as bool? ?? false,
      useSsl: json['useSsl'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'endpoint': endpoint,
      'region': region,
      'bucketName': bucketName,
      'accessKey': accessKey,
      'secretKey': secretKey,
      'remotePrefix': remotePrefix,
      'usePathStyle': usePathStyle,
      'useSsl': useSsl,
    };
  }

  S3Config copyWith({
    bool? enabled,
    String? endpoint,
    String? region,
    String? bucketName,
    String? accessKey,
    String? secretKey,
    String? remotePrefix,
    bool? usePathStyle,
    bool? useSsl,
  }) {
    return S3Config(
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      region: region ?? this.region,
      bucketName: bucketName ?? this.bucketName,
      accessKey: accessKey ?? this.accessKey,
      secretKey: secretKey ?? this.secretKey,
      remotePrefix: remotePrefix ?? this.remotePrefix,
      usePathStyle: usePathStyle ?? this.usePathStyle,
      useSsl: useSsl ?? this.useSsl,
    );
  }

  bool get isValid =>
      endpoint.trim().isNotEmpty &&
      bucketName.trim().isNotEmpty &&
      accessKey.trim().isNotEmpty &&
      secretKey.trim().isNotEmpty;
}
