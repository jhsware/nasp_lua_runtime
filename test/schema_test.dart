import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('schema validation', () {
    final schema = Schema([
      Field('name', TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true)),
      Field('age', TypeSpec.integer(), constraint: const Constraint(min: 0)),
      Field('tags', TypeSpec.list(TypeSpec.string()), required: false),
      Field('when', TypeSpec.timestamp()),
    ]);

    Map<String, Object?> valid() => {
          'name': 'Ada',
          'age': 30,
          'when': '2026-01-01T00:00:00Z',
        };

    test('coerces a valid object', () {
      final out =
          schema.validate(valid(), part: ScriptKind.scheduling, input: true);
      expect(out['name'], 'Ada');
      expect(out['age'], 30);
      expect(out['when'], isA<DateTime>());
      expect((out['when'] as DateTime).toUtc().toIso8601String(),
          '2026-01-01T00:00:00.000Z');
      expect(out.containsKey('tags'), isFalse); // optional + absent -> omitted
    });

    test('reports a path-qualified error for a wrong nested type', () {
      final nested = Schema([
        Field(
          'entries',
          TypeSpec.list(TypeSpec.object([
            Field('trigger_at', TypeSpec.timestamp()),
          ])),
        ),
      ]);
      expect(
        () => nested.validate({
          'entries': [
            {'trigger_at': '2026-01-01T00:00:00Z'},
            {'trigger_at': 'not-a-date'},
          ],
        }, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
            .having((e) => e.path, 'path', 'entries[1].trigger_at')),
      );
    });

    test('missing required field is inputInvalid', () {
      final bad = valid()..remove('name');
      expect(
        () => schema.validate(bad, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>().having((e) => e.path, 'path', 'name')),
      );
    });

    test('constraint violations are path-qualified', () {
      final empty = valid()..['name'] = '';
      expect(
        () => schema.validate(empty, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>().having((e) => e.path, 'path', 'name')),
      );
      final negative = valid()..['age'] = -1;
      expect(
        () =>
            schema.validate(negative, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>().having((e) => e.path, 'path', 'age')),
      );
    });

    test('output validation uses outputInvalid', () {
      final bad = valid()..['age'] = 'thirty';
      expect(
        () => schema.validate(bad, part: ScriptKind.scheduling, input: false),
        throwsA(isA<ScriptError>()
            .having((e) => e.type, 'type', ScriptErrorType.outputInvalid)),
      );
    });
  });

  group('contract descriptors', () {
    test('scheduling descriptor', () {
      final d = contractFor(ScriptKind.scheduling)!;
      expect(d.entrypoint, 'schedule');
      expect(d.ioContractVersion, 1);
      final json = d.toJson();
      expect(json['kind'], 'scheduling');
      expect(json['io_contract_version'], 1);
      expect((json['input'] as Map)['type'], 'object');
      expect((json['output'] as Map)['type'], 'object');
    });

    test('question_selection descriptor', () {
      final d = contractFor(ScriptKind.questionSelection)!;
      expect(d.entrypoint, 'select_questions');
      expect(d.ioContractVersion, 1);
      expect(d.toJson()['kind'], 'question_selection');
    });

    test('follow_up descriptor', () {
      final d = contractFor(ScriptKind.followUp)!;
      expect(d.entrypoint, 'follow_up');
      expect(d.ioContractVersion, 1);
      final json = d.toJson();
      expect(json['kind'], 'follow_up');
      expect(json['io_contract_version'], 1);
      expect(ScriptKind.fromId('follow_up'), ScriptKind.followUp);
      // Output is an optional/nullable follow_up object — absent/null means
      // "no follow-up round".
      final outFields = ((json['output'] as Map)['fields'] as List).cast<Map>();
      final fu = outFields.firstWhere((f) => f['name'] == 'follow_up');
      expect(fu['required'], isFalse);
      expect(fu['nullable'], isTrue);
      // Distinguishing invariant: the follow_up input carries answer values.
      final inFields = ((json['input'] as Map)['fields'] as List).cast<Map>();
      final currentRound =
          inFields.firstWhere((f) => f['name'] == 'current_round');
      final roundFields =
          ((currentRound['type'] as Map)['fields'] as List).cast<Map>();
      final answers = roundFields.firstWhere((f) => f['name'] == 'answers');
      final answerFields =
          (((answers['type'] as Map)['element'] as Map)['fields'] as List)
              .cast<Map>();
      expect(answerFields.map((f) => f['name']), contains('values'));
    });

    test('registry covers every kind', () {
      for (final k in ScriptKind.values) {
        expect(contractFor(k), isNotNull, reason: 'no contract for ${k.id}');
      }
    });

    test('ScriptKind.fromId round-trips', () {
      for (final k in ScriptKind.values) {
        expect(ScriptKind.fromId(k.id), k);
      }
      expect(ScriptKind.fromId('nope'), isNull);
    });
  });

  group('scheduling study_length_days', () {
    Schema schedInput() => contractFor(ScriptKind.scheduling)!.input;

    Map<String, Object?> validSched() => {
          'timezone': 'Europe/Stockholm',
          'study_window': {
            'start': '2026-01-01T00:00:00Z',
            'end': '2026-12-31T00:00:00Z',
          },
          'settings': {
            'id': 's1',
            'scope': 'study',
            'version': 1,
            'state': 'published',
            'rule': <String, Object?>{},
          },
          'enrolment_date': '2026-01-01T00:00:00Z',
          'now': '2026-06-01T00:00:00Z',
          'horizon_days': 7,
        };

    test('is optional — input without it still validates', () {
      final out = schedInput()
          .validate(validSched(), part: ScriptKind.scheduling, input: true);
      expect(out.containsKey('study_length_days'), isFalse);
    });

    test('present value is coerced through', () {
      final input = validSched()..['study_length_days'] = 7;
      final out = schedInput()
          .validate(input, part: ScriptKind.scheduling, input: true);
      expect(out['study_length_days'], 7);
    });

    test('explicit null is accepted and behaves like absent', () {
      final input = validSched()..['study_length_days'] = null;
      final out = schedInput()
          .validate(input, part: ScriptKind.scheduling, input: true);
      expect(out['study_length_days'], isNull);
    });

    test('zero is rejected (min 1) with a path-qualified error', () {
      final input = validSched()..['study_length_days'] = 0;
      expect(
        () => schedInput()
            .validate(input, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
            .having((e) => e.path, 'path', 'study_length_days')),
      );
    });

    test('descriptor lists study_length_days as optional int min 1', () {
      final fields = (contractFor(ScriptKind.scheduling)!.toJson()['input']
          as Map)['fields'] as List;
      final field = fields
          .firstWhere((f) => (f as Map)['name'] == 'study_length_days') as Map;
      expect((field['type'] as Map)['type'], 'int');
      expect(field['required'], isFalse);
      expect(field['nullable'], isTrue);
      expect((field['constraint'] as Map)['min'], 1);
    });
  });

  group('wire-shape parsing (Schema.fromJson)', () {
    test('round-trips a schema with every scalar type and constraints', () {
      final schema = Schema([
        Field('flag', TypeSpec.boolean(), defaultValue: true),
        Field('count', TypeSpec.integer(),
            constraint: const Constraint(min: 0, max: 10), defaultValue: 3),
        Field('ratio', TypeSpec.doubleValue(), required: false),
        Field('label', TypeSpec.string(),
            constraint: const Constraint(nonEmpty: true)),
        Field('mode', TypeSpec.enumeration(['a', 'b']), defaultValue: 'a'),
        Field('start', TypeSpec.timestamp()),
        Field('tags', TypeSpec.list(TypeSpec.string()), required: false),
        Field('extra', TypeSpec.json(), required: false, nullable: true),
      ]);
      final parsed = Schema.fromJson(schema.toJson());
      expect(parsed.toJson(), schema.toJson());
    });

    test('round-trips nested objects and maps', () {
      final schema = Schema([
        Field(
          'window',
          TypeSpec.object([
            Field('start', TypeSpec.timestamp()),
            Field('end', TypeSpec.timestamp()),
          ]),
        ),
        Field('meta', TypeSpec.map(TypeSpec.string()), required: false),
      ]);
      expect(Schema.fromJson(schema.toJson()).toJson(), schema.toJson());
    });

    test('a parsed schema validates values', () {
      final parsed = Schema.fromJson(Schema([
        Field('interval_days', TypeSpec.integer(),
            constraint: const Constraint(min: 1)),
      ]).toJson());
      final out = parsed.validate({'interval_days': 2},
          part: ScriptKind.scheduling, input: true);
      expect(out['interval_days'], 2);
      expect(
        () => parsed.validate({'interval_days': 0},
            part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.path, 'path', 'interval_days')),
      );
      expect(
        () => parsed.validate({'interval_days': 'x'},
            part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.path, 'path', 'interval_days')),
      );
    });

    test('default is carried on the wire and optional', () {
      final json = Schema([
        Field('count', TypeSpec.integer(), defaultValue: 5),
        Field('label', TypeSpec.string()),
      ]).toJson();
      final fields = (json['fields'] as List).cast<Map>();
      expect(fields[0]['default'], 5);
      expect(fields[1].containsKey('default'), isFalse);
      final parsed = Schema.fromJson(json);
      expect(parsed.fields[0].defaultValue, 5);
      expect(parsed.fields[1].defaultValue, isNull);
    });

    test('rejects malformed descriptors with path-qualified messages', () {
      expect(() => Schema.fromJson(null), throwsFormatException);
      expect(() => Schema.fromJson({'type': 'int'}), throwsFormatException);
      expect(
        () => Schema.fromJson({'type': 'object'}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('fields'))),
      );
      expect(
        () => Schema.fromJson({
          'type': 'object',
          'fields': [
            {'name': 'x', 'type': {'type': 'nope'}},
          ],
        }),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('.fields[0].type'))),
      );
      expect(
        () => Schema.fromJson({
          'type': 'object',
          'fields': [
            {'name': '', 'type': {'type': 'int'}},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => Schema.fromJson({
          'type': 'object',
          'fields': [
            {'name': 'mode', 'type': {'type': 'enum', 'values': []}},
          ],
        }),
        throwsFormatException,
      );
    });

    test('contract descriptors survive a parse round-trip', () {
      for (final kind in ScriptKind.values) {
        final d = contractFor(kind)!;
        expect(Schema.fromJson(d.toJson()['input']).toJson(),
            d.input.toJson());
        expect(Schema.fromJson(d.toJson()['output']).toJson(),
            d.output.toJson());
      }
    });
  });
}