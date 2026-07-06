/// The explicit, dependency-free schema type and its validator
/// (docs/design/scripting.md §4.2).
///
/// Contracts use a small, explicit schema type — not free-form JSON Schema —
/// so validation is identical on every platform with no external dependency.
/// A schema describes an object with typed, optionally-nullable fields. The
/// validator coerces a raw JSON-like value into a typed Dart value or raises a
/// precise, path-qualified [ScriptError] (e.g. `triggers[3].trigger_at:
/// expected timestamp`).
///
/// A [Schema] serialised to JSON together with the kind's entry-point name is
/// exactly the **contract descriptor** returned by
/// `GET /script-bundles/contracts?kind=` (§4.1, §7).
library;

import 'errors.dart';

/// The primitive and complex types a contract field may take (§4.2).
enum SchemaType {
  boolean,
  integer,
  doubleValue,
  string,
  enumeration,
  timestamp,
  list,
  map,
  object,

  /// Pragmatic escape hatch for genuinely free-form JSON — used for the
  /// resolved schedule `rule`, which the `nasp_scheduling` domain persists as
  /// an opaque JSON blob (`ScheduleSettingsRow.rule`). It is marshalled
  /// losslessly in both directions but not field-type-checked.
  json,
}

/// A (possibly nested) type in the schema tree.
class TypeSpec {
  TypeSpec._(this.type, {this.element, this.value, this.fields, this.enumValues});

  final SchemaType type;

  /// Element type for [SchemaType.list].
  final TypeSpec? element;

  /// Value type for [SchemaType.map] (keys are always strings).
  final TypeSpec? value;

  /// Fields for [SchemaType.object].
  final List<Field>? fields;

  /// Allowed values for [SchemaType.enumeration].
  final List<String>? enumValues;

  TypeSpec.boolean() : this._(SchemaType.boolean);
  TypeSpec.integer() : this._(SchemaType.integer);
  TypeSpec.doubleValue() : this._(SchemaType.doubleValue);
  TypeSpec.string() : this._(SchemaType.string);
  TypeSpec.timestamp() : this._(SchemaType.timestamp);
  TypeSpec.json() : this._(SchemaType.json);
  TypeSpec.enumeration(List<String> values)
      : this._(SchemaType.enumeration, enumValues: values);
  TypeSpec.list(TypeSpec element) : this._(SchemaType.list, element: element);
  TypeSpec.map(TypeSpec value) : this._(SchemaType.map, value: value);
  TypeSpec.object(List<Field> fields)
      : this._(SchemaType.object, fields: fields);

  /// Short name used in descriptor JSON and error messages.
  String get wireName {
    switch (type) {
      case SchemaType.boolean:
        return 'bool';
      case SchemaType.integer:
        return 'int';
      case SchemaType.doubleValue:
        return 'double';
      case SchemaType.string:
        return 'string';
      case SchemaType.enumeration:
        return 'enum';
      case SchemaType.timestamp:
        return 'timestamp';
      case SchemaType.list:
        return 'list';
      case SchemaType.map:
        return 'map';
      case SchemaType.object:
        return 'object';
      case SchemaType.json:
        return 'json';
    }
  }

  /// The descriptor JSON for this type (frozen wire shape).
  Map<String, Object?> toJson() {
    switch (type) {
      case SchemaType.boolean:
      case SchemaType.integer:
      case SchemaType.doubleValue:
      case SchemaType.string:
      case SchemaType.timestamp:
      case SchemaType.json:
        return {'type': wireName};
      case SchemaType.enumeration:
        return {'type': 'enum', 'values': List<String>.of(enumValues!)};
      case SchemaType.list:
        return {'type': 'list', 'element': element!.toJson()};
      case SchemaType.map:
        return {'type': 'map', 'value': value!.toJson()};
      case SchemaType.object:
        return {
          'type': 'object',
          'fields': fields!.map((f) => f.toJson()).toList(),
        };
    }
  }
}

/// An optional per-field constraint (§4.2: "range, non-empty, allowed values").
class Constraint {
  const Constraint({this.min, this.max, this.nonEmpty = false});

  /// Inclusive lower bound for numeric fields.
  final num? min;

  /// Inclusive upper bound for numeric fields.
  final num? max;

  /// For strings and lists: the value must be non-empty.
  final bool nonEmpty;

  Map<String, Object?> toJson() => {
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (nonEmpty) 'non_empty': true,
      };
}

/// One field of an object schema.
class Field {
  const Field(
    this.name,
    this.type, {
    this.required = true,
    this.nullable = false,
    this.constraint,
  });

  final String name;
  final TypeSpec type;

  /// Whether the key must be present.
  final bool required;

  /// Whether an explicit `null` value is allowed when present.
  final bool nullable;

  final Constraint? constraint;

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type.toJson(),
        'required': required,
        'nullable': nullable,
        if (constraint != null) 'constraint': constraint!.toJson(),
      };
}

/// A top-level object schema — the input or output side of a contract.
class Schema {
  const Schema(this.fields);

  final List<Field> fields;

  /// This schema expressed as a [TypeSpec] (an object type).
  TypeSpec get asType => TypeSpec.object(fields);

  /// Validate and coerce a raw JSON-like [json] into a typed Dart map.
  ///
  /// [input] selects the error type ([ScriptErrorType.inputInvalid] vs
  /// [ScriptErrorType.outputInvalid]); [part] attributes the error to a kind.
  /// Throws [ScriptError] with a path on the first violation.
  Map<String, Object?> validate(
    Object? json, {
    required ScriptKind part,
    required bool input,
  }) {
    final v = _Validator(part, input);
    final result = v.coerce(asType, json, '');
    return (result as Map<String, Object?>);
  }

  /// The descriptor JSON for this schema.
  Map<String, Object?> toJson() => asType.toJson();
}

/// A full per-kind contract descriptor: the input + output schemas plus the
/// entry-point name and contract version. This is what
/// `GET /script-bundles/contracts?kind=` serialises (§4.1, §7).
class ContractDescriptor {
  const ContractDescriptor({
    required this.kind,
    required this.entrypoint,
    required this.ioContractVersion,
    required this.input,
    required this.output,
  });

  final ScriptKind kind;

  /// The global Lua function the runtime invokes for this kind.
  final String entrypoint;

  /// The integer contract revision this descriptor represents (§4.5).
  final int ioContractVersion;

  final Schema input;
  final Schema output;

  Map<String, Object?> toJson() => {
        'kind': kind.id,
        'entrypoint': entrypoint,
        'io_contract_version': ioContractVersion,
        'input': input.toJson(),
        'output': output.toJson(),
      };
}

/// Walks a [TypeSpec] coercing raw JSON into typed Dart values, raising a
/// path-qualified [ScriptError] on the first mismatch.
class _Validator {
  _Validator(this.part, this.input);

  final ScriptKind part;
  final bool input;

  Never _fail(String path, String message) {
    throw ScriptError(
      type: input ? ScriptErrorType.inputInvalid : ScriptErrorType.outputInvalid,
      part: part,
      message: message,
      path: path,
    );
  }

  Object? coerce(TypeSpec spec, Object? json, String path) {
    switch (spec.type) {
      case SchemaType.boolean:
        if (json is bool) return json;
        _fail(path, 'expected bool');
      case SchemaType.integer:
        if (json is int) return json;
        _fail(path, 'expected int');
      case SchemaType.doubleValue:
        if (json is num) return json.toDouble();
        _fail(path, 'expected double');
      case SchemaType.string:
        if (json is String) return json;
        _fail(path, 'expected string');
      case SchemaType.enumeration:
        if (json is String && spec.enumValues!.contains(json)) return json;
        _fail(path, 'expected one of ${spec.enumValues}');
      case SchemaType.timestamp:
        return _timestamp(json, path);
      case SchemaType.list:
        if (json is! List) _fail(path, 'expected list');
        final out = <Object?>[];
        for (var i = 0; i < json.length; i++) {
          out.add(coerce(spec.element!, json[i], '$path[$i]'));
        }
        return out;
      case SchemaType.map:
        if (json is! Map) _fail(path, 'expected map');
        final out = <String, Object?>{};
        json.forEach((k, v) {
          final key = k.toString();
          out[key] = coerce(spec.value!, v, path.isEmpty ? key : '$path.$key');
        });
        return out;
      case SchemaType.object:
        return _object(spec.fields!, json, path);
      case SchemaType.json:
        return _json(json, path);
    }
  }

  DateTime _timestamp(Object? json, String path) {
    if (json is String) {
      final dt = DateTime.tryParse(json);
      if (dt == null) _fail(path, 'expected timestamp (ISO-8601)');
      return dt.toUtc();
    }
    if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json * 1000, isUtc: true);
    }
    if (json is double) {
      return DateTime.fromMillisecondsSinceEpoch((json * 1000).round(),
          isUtc: true);
    }
    _fail(path, 'expected timestamp');
  }

  Map<String, Object?> _object(List<Field> fields, Object? json, String path) {
    if (json is! Map) _fail(path, 'expected object');
    final out = <String, Object?>{};
    for (final field in fields) {
      final fpath = path.isEmpty ? field.name : '$path.${field.name}';
      final present = json.containsKey(field.name);
      if (!present) {
        if (field.required) _fail(fpath, 'missing required field');
        continue;
      }
      final raw = json[field.name];
      if (raw == null) {
        if (field.nullable) {
          out[field.name] = null;
          continue;
        }
        _fail(fpath, 'expected ${field.type.wireName}, got null');
      }
      final coerced = coerce(field.type, raw, fpath);
      _constrain(field.constraint, coerced, fpath);
      out[field.name] = coerced;
    }
    return out;
  }

  void _constrain(Constraint? c, Object? value, String path) {
    if (c == null) return;
    if (value is num) {
      if (c.min != null && value < c.min!) _fail(path, 'must be >= ${c.min}');
      if (c.max != null && value > c.max!) _fail(path, 'must be <= ${c.max}');
    }
    if (c.nonEmpty) {
      if (value is String && value.isEmpty) _fail(path, 'must be non-empty');
      if (value is List && value.isEmpty) _fail(path, 'must be non-empty');
    }
  }

  /// Validate that [json] is a JSON-representable value and return it as-is
  /// (numbers keep their int/double identity).
  Object? _json(Object? json, String path) {
    if (json == null || json is bool || json is num || json is String) {
      return json;
    }
    if (json is List) {
      for (var i = 0; i < json.length; i++) {
        _json(json[i], '$path[$i]');
      }
      return json;
    }
    if (json is Map) {
      json.forEach((k, v) => _json(v, path.isEmpty ? '$k' : '$path.$k'));
      return json;
    }
    _fail(path, 'expected JSON value');
  }
}
