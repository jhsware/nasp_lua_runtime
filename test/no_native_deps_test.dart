import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Guards the subsystem's cross-platform promise: `nasp_lua_runtime` must stay
/// pure Dart so it runs unchanged on the server and (later) the iOS/Android
/// app. If this package ever grows a Flutter/FFI/native dependency the shared
/// runtime can no longer be byte-identical across hosts.
void main() {
  test('package declares no Flutter/FFI/native dependencies', () async {
    final libUri = await Isolate.resolvePackageUri(
        Uri.parse('package:nasp_lua_runtime/nasp_lua_runtime.dart'));
    if (libUri == null) {
      markTestSkipped('could not resolve package URI');
      return;
    }
    // .../nasp_lua_runtime/lib/nasp_lua_runtime.dart -> ../pubspec.yaml
    final pubspec = File.fromUri(libUri.resolve('../pubspec.yaml'));
    expect(pubspec.existsSync(), isTrue,
        reason: 'pubspec not found at ${pubspec.path}');
    final text = pubspec.readAsStringSync();
    for (final banned in const [
      'flutter',
      'ffi',
      'ffigen',
      'native_toolchain',
      'native_assets',
      'jni',
    ]) {
      expect(text.contains(banned), isFalse,
          reason: 'forbidden dependency token "$banned" in pubspec.yaml');
    }
  });
}
