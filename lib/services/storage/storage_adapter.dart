import 'dart:io';

abstract class StorageAdapter {
  String get name;
  Future<bool> testConnection();
  Future<bool> uploadFile({
    required File file,
    required String remoteRelativePath,
    void Function(double progress)? onProgress,
  });
  Future<List<String>> listRemoteFiles(String remoteDir);
}
