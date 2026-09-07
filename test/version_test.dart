import 'dart:io';
import 'dart:isolate';

import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

/// Guards `LuaScriptRuntime.version` against drift from the package version.
/// A host compares a bundle's `runtime_min_version` against the constant, so a
/// stale constant makes that check wrong (it was stuck at 0.1.0 until 0.7.0).
void main() {
  test('LuaScriptRuntime.version equals the pubspec version', () async {
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
    final line = pubspec
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'no "version:" line in pubspec.yaml');
    final pubspecVersion = line.substring('version:'.length).trim();
    expect(pubspecVersion, isNotEmpty);
    expect(LuaScriptRuntime.version, equals(pubspecVersion));
  });
}
