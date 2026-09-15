/// Total, lossless Dart <-> Lua marshalling for the schema types
/// (docs/design/scripting.md §4.4).
///
/// This is the boundary [LuaScriptRuntime.run] crosses in both directions:
/// Dart maps/lists <-> Lua tables, timestamps <-> epoch seconds, with the
/// integer/double distinction preserved. Reads are schema-driven so a Lua
/// table is interpreted as a list, map, or object exactly as the output
/// contract expects, and any mismatch is a path-qualified
/// [ScriptErrorType.outputInvalid].
library;

import 'package:lua_dardo_plus/lua.dart';

import 'errors.dart';
import 'schema.dart';

/// Push a coerced Dart [value] onto the Lua stack.
///
/// Accepts the typed values produced by [Schema.validate] plus raw JSON values
/// (for [SchemaType.json] fields). Timestamps ([DateTime]) surface to Lua as
/// integer epoch seconds. Throws [ArgumentError] for an unmarshalable type.
void pushDartValue(LuaState ls, Object? value) {
  if (value == null) {
    ls.pushNil();
  } else if (value is bool) {
    ls.pushBoolean(value);
  } else if (value is int) {
    ls.pushInteger(value);
  } else if (value is double) {
    ls.pushNumber(value);
  } else if (value is String) {
    ls.pushString(value);
  } else if (value is DateTime) {
    ls.pushInteger(value.toUtc().millisecondsSinceEpoch ~/ 1000);
  } else if (value is List) {
    ls.newTable();
    final t = ls.getTop();
    for (var i = 0; i < value.length; i++) {
      pushDartValue(ls, value[i]);
      ls.rawSetI(t, i + 1);
    }
  } else if (value is Map) {
    ls.newTable();
    final t = ls.getTop();
    value.forEach((k, v) {
      pushDartValue(ls, v);
      ls.setField(t, k.toString());
    });
  } else {
    throw ArgumentError('unmarshalable Dart value: ${value.runtimeType}');
  }
}

/// Read the Lua value on top of the stack as the Dart value the [spec]
/// describes. The value is left on the stack (the caller pops). Raises a
/// path-qualified [ScriptError] ([ScriptErrorType.outputInvalid]) on mismatch.
Object? readLuaValue(LuaState ls, TypeSpec spec, String path, ScriptKind part) {
  switch (spec.type) {
    case SchemaType.boolean:
      if (!ls.isBoolean(-1)) _fail(part, path, 'expected bool');
      return ls.toBoolean(-1);
    case SchemaType.integer:
      if (!ls.isInteger(-1)) _fail(part, path, 'expected int');
      return ls.toInteger(-1);
    case SchemaType.doubleValue:
      if (!ls.isNumber(-1)) _fail(part, path, 'expected double');
      return ls.toNumber(-1);
    case SchemaType.string:
      if (!_isRealString(ls)) _fail(part, path, 'expected string');
      return ls.toStr(-1);
    case SchemaType.enumeration:
      if (!_isRealString(ls)) _fail(part, path, 'expected string');
      final s = ls.toStr(-1);
      if (!spec.enumValues!.contains(s)) {
        _fail(part, path, 'expected one of ${spec.enumValues}');
      }
      return s;
    case SchemaType.timestamp:
      if (!ls.isNumber(-1)) {
        _fail(part, path, 'expected timestamp (epoch seconds)');
      }
      final secs = ls.toNumber(-1);
      return DateTime.fromMillisecondsSinceEpoch((secs * 1000).round(),
          isUtc: true);
    case SchemaType.list:
      if (!ls.isTable(-1)) _fail(part, path, 'expected list');
      final n = ls.rawLen(-1);
      final out = <Object?>[];
      for (var i = 1; i <= n; i++) {
        ls.rawGetI(-1, i);
        out.add(readLuaValue(ls, spec.element!, '$path[${i - 1}]', part));
        ls.pop(1);
      }
      return out;
    case SchemaType.map:
      if (!ls.isTable(-1)) _fail(part, path, 'expected map');
      return _readMap(ls, spec.value!, path, part);
    case SchemaType.object:
      if (!ls.isTable(-1)) _fail(part, path, 'expected object');
      return _readObject(ls, spec.fields!, path, part);
    case SchemaType.json:
      return _readJson(ls, path, part);
  }
}

Map<String, Object?> _readMap(
    LuaState ls, TypeSpec value, String path, ScriptKind part) {
  final out = <String, Object?>{};
  final t = ls.getTop();
  ls.pushNil();
  while (ls.next(t)) {
    final key = ls.toStr(-2) ?? '';
    out[key] =
        readLuaValue(ls, value, path.isEmpty ? key : '$path.$key', part);
    ls.pop(1); // pop value, keep key for the next iteration
  }
  return out;
}

Map<String, Object?> _readObject(
    LuaState ls, List<Field> fields, String path, ScriptKind part) {
  final out = <String, Object?>{};
  for (final field in fields) {
    final fpath = path.isEmpty ? field.name : '$path.${field.name}';
    ls.getField(-1, field.name); // pushes the field value (nil if absent)
    if (ls.isNil(-1)) {
      ls.pop(1);
      if (field.nullable) {
        out[field.name] = null;
      } else if (field.required) {
        _fail(part, fpath, 'missing required field');
      }
      continue;
    }
    final v = readLuaValue(ls, field.type, fpath, part);
    _constrain(part, field.constraint, v, fpath);
    ls.pop(1);
    out[field.name] = v;
  }
  return out;
}

Object? _readJson(LuaState ls, String path, ScriptKind part) {
  if (ls.isNil(-1)) return null;
  if (ls.isBoolean(-1)) return ls.toBoolean(-1);
  if (ls.isInteger(-1)) return ls.toInteger(-1);
  if (ls.isNumber(-1)) return ls.toNumber(-1);
  if (_isRealString(ls)) return ls.toStr(-1);
  if (ls.isTable(-1)) {
    final n = ls.rawLen(-1);
    if (n > 0) {
      final out = <Object?>[];
      for (var i = 1; i <= n; i++) {
        ls.rawGetI(-1, i);
        out.add(_readJson(ls, '$path[${i - 1}]', part));
        ls.pop(1);
      }
      return out;
    }
    final out = <String, Object?>{};
    final t = ls.getTop();
    ls.pushNil();
    while (ls.next(t)) {
      final key = ls.toStr(-2) ?? '';
      out[key] = _readJson(ls, path.isEmpty ? key : '$path.$key', part);
      ls.pop(1);
    }
    return out;
  }
  _fail(part, path, 'unsupported Lua value');
}

/// True when the top value is a genuine string (Lua reports numbers as
/// convertible-to-string; we exclude those).
bool _isRealString(LuaState ls) => ls.isString(-1) && !ls.isNumber(-1);

void _constrain(ScriptKind part, Constraint? c, Object? value, String path) {
  if (c == null) return;
  if (value is num) {
    final min = c.numMin;
    final max = c.numMax;
    if (min != null && value < min) _fail(part, path, 'must be >= $min');
    if (max != null && value > max) _fail(part, path, 'must be <= $max');
  }
  if (c.nonEmpty) {
    if (value is String && value.isEmpty) _fail(part, path, 'must be non-empty');
    if (value is List && value.isEmpty) _fail(part, path, 'must be non-empty');
  }
}

Never _fail(ScriptKind part, String path, String message) {
  throw ScriptError(
    type: ScriptErrorType.outputInvalid,
    part: part,
    message: message,
    path: path,
  );
}
