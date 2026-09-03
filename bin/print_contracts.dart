/// Prints the frozen contract descriptor of every kind as pretty JSON —
/// exactly what `GET /script-bundles/contracts?kind=` serves.
///
///     dart run bin/print_contracts.dart [kind ...]
library;

import 'dart:convert';

import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';

void main(List<String> args) {
  final kinds = args.isEmpty
      ? ScriptKind.values
      : args.map((a) {
          final k = ScriptKind.fromId(a);
          if (k == null) throw ArgumentError('unknown kind "$a"');
          return k;
        }).toList();
  const encoder = JsonEncoder.withIndent('  ');
  for (final kind in kinds) {
    print(encoder.convert(contractFor(kind)!.toJson()));
  }
}
