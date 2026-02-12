// Stub file for web platform
// This file is only used when dart:io is not available (web platform)

import 'dart:typed_data';

class File {
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  Future<Uint8List> readAsBytes() async =>
      throw UnimplementedError('File operations not available on web');
  Future<void> delete() async =>
      throw UnimplementedError('File operations not available on web');
}
