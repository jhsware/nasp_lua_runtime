import 'dart:convert';

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
      expect(d.ioContractVersion, 2);
      final json = d.toJson();
      expect(json['kind'], 'scheduling');
      expect(json['io_contract_version'], 2);
      expect((json['input'] as Map)['type'], 'object');
      expect((json['output'] as Map)['type'], 'object');
    });

    test('question_selection descriptor', () {
      final d = contractFor(ScriptKind.questionSelection)!;
      expect(d.entrypoint, 'select_questions');
      expect(d.ioContractVersion, 2);
      expect(d.toJson()['kind'], 'question_selection');
    });

    test('follow_up descriptor', () {
      final d = contractFor(ScriptKind.followUp)!;
      expect(d.entrypoint, 'follow_up');
      expect(d.ioContractVersion, 2);
      final json = d.toJson();
      expect(json['kind'], 'follow_up');
      expect(json['io_contract_version'], 2);
      expect(ScriptKind.fromId('follow_up'), ScriptKind.followUp);
      // Output is an optional/nullable follow_up object — absent/null means
      // "no follow-up round".
      final outFields = ((json['output'] as Map)['fields'] as List).cast<Map>();
      final fu = outFields.firstWhere((f) => f['name'] == 'follow_up');
      expect(fu['required'], isFalse);
      expect(fu['nullable'], isTrue);
      // Distinguishing invariant: the follow_up input carries answer values
      // (under the `signals` group in contract v2).
      final inFields = ((json['input'] as Map)['fields'] as List).cast<Map>();
      final signals = inFields.firstWhere((f) => f['name'] == 'signals');
      final signalFields =
          ((signals['type'] as Map)['fields'] as List).cast<Map>();
      final currentRound =
          signalFields.firstWhere((f) => f['name'] == 'current_round');
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

    test('no contract field carries a description (prose lives server-side)',
        () {
      bool hasDescription(Map<String, Object?> node) {
        if (node.containsKey('description')) return true;
        final fields = node['fields'];
        if (fields is List) {
          for (final f in fields) {
            if (hasDescription((f as Map).cast<String, Object?>())) return true;
            if (hasDescription((f['type'] as Map).cast<String, Object?>())) {
              return true;
            }
          }
        }
        final element = node['element'];
        if (element is Map && hasDescription(element.cast<String, Object?>())) {
          return true;
        }
        final value = node['value'];
        if (value is Map && hasDescription(value.cast<String, Object?>())) {
          return true;
        }
        return false;
      }

      for (final k in ScriptKind.values) {
        final json = contractFor(k)!.toJson();
        expect(hasDescription((json['input'] as Map).cast<String, Object?>()),
            isFalse,
            reason: '${k.id} input');
        expect(hasDescription((json['output'] as Map).cast<String, Object?>()),
            isFalse,
            reason: '${k.id} output');
      }
    });
  });

  group('scheduling study.length_days', () {
    Schema schedInput() => contractFor(ScriptKind.scheduling)!.input;

    Map<String, Object?> validSched() => {
          'study': <String, Object?>{
            'timezone': 'Europe/Stockholm',
            'window': <String, Object?>{
              'start': '2026-01-01T00:00:00Z',
              'end': '2026-12-31T00:00:00Z',
            },
            'horizon_days': 7,
          },
          'settings': <String, Object?>{
            'id': 's1',
            'scope': 'study',
            'version': 1,
            'state': 'published',
            'rule': <String, Object?>{},
          },
          'signals': <String, Object?>{
            'participant_id': 'p1',
            'enrolment_date': '2026-01-01T00:00:00Z',
          },
          'now': '2026-06-01T00:00:00Z',
        };

    Map<String, Object?> study(Map<String, Object?> input) =>
        input['study'] as Map<String, Object?>;

    test('is optional — input without it still validates', () {
      final out = schedInput()
          .validate(validSched(), part: ScriptKind.scheduling, input: true);
      expect(study(out).containsKey('length_days'), isFalse);
    });

    test('present value is coerced through', () {
      final input = validSched();
      study(input)['length_days'] = 7;
      final out = schedInput()
          .validate(input, part: ScriptKind.scheduling, input: true);
      expect(study(out)['length_days'], 7);
    });

    test('explicit null is accepted and behaves like absent', () {
      final input = validSched();
      study(input)['length_days'] = null;
      final out = schedInput()
          .validate(input, part: ScriptKind.scheduling, input: true);
      expect(study(out)['length_days'], isNull);
    });

    test('zero is rejected (min 1) with a path-qualified error', () {
      final input = validSched();
      study(input)['length_days'] = 0;
      expect(
        () => schedInput()
            .validate(input, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
            .having((e) => e.path, 'path', 'study.length_days')),
      );
    });

    test('descriptor lists study.length_days as optional int min 1', () {
      final fields = (contractFor(ScriptKind.scheduling)!.toJson()['input']
          as Map)['fields'] as List;
      final studyField =
          fields.firstWhere((f) => (f as Map)['name'] == 'study') as Map;
      final studyFields = (studyField['type'] as Map)['fields'] as List;
      final field = studyFields
          .firstWhere((f) => (f as Map)['name'] == 'length_days') as Map;
      expect((field['type'] as Map)['type'], 'int');
      expect(field['required'], isFalse);
      expect(field['nullable'], isTrue);
      expect((field['constraint'] as Map)['min'], 1);
    });

    test('a missing signals group is reported at `signals`', () {
      final input = validSched()..remove('signals');
      expect(
        () => schedInput()
            .validate(input, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
            .having((e) => e.path, 'path', 'signals')),
      );
    });

    test('an empty signals.participant_id is rejected', () {
      final input = validSched();
      (input['signals'] as Map<String, Object?>)['participant_id'] = '';
      expect(
        () => schedInput()
            .validate(input, part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.path, 'path', 'signals.participant_id')),
      );
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

    test('description round-trips through Field.fromJson / toJson', () {
      final field = Field.fromJson({
        'name': 'x',
        'type': {'type': 'int'},
        'description': 'how many',
      });
      expect(field.description, 'how many');
      final json = field.toJson();
      expect(json['description'], 'how many');
      expect(Field.fromJson(json).toJson(), json);
      // Through a whole schema too.
      final schema = Schema([
        Field('count', TypeSpec.integer(),
            defaultValue: 3, description: 'How many prompts per day.'),
      ]);
      expect(Schema.fromJson(schema.toJson()).toJson(), schema.toJson());
      expect(Schema.fromJson(schema.toJson()).fields[0].description,
          'How many prompts per day.');
    });

    test('a field without a description has no description key', () {
      final json = Field('x', TypeSpec.integer()).toJson();
      expect(json.containsKey('description'), isFalse);
      expect(json.keys.toList(), ['name', 'type', 'required', 'nullable']);
      expect(Field.fromJson(json).description, isNull);
    });

    test('a non-string description is a path-qualified FormatException', () {
      expect(
        () => Field.fromJson({
          'name': 'x',
          'type': {'type': 'int'},
          'description': 3,
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('description'))),
      );
      expect(
        () => Schema.fromJson({
          'type': 'object',
          'fields': [
            {'name': 'x', 'type': {'type': 'int'}, 'description': 3},
          ],
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('.fields[0]'))
            .having((e) => e.message, 'message', contains('description'))),
      );
    });

    test('the validator ignores descriptions', () {
      final schema = Schema([
        Field('count', TypeSpec.integer(), description: 'ignored'),
      ]);
      final out = schema.validate({'count': 2},
          part: ScriptKind.scheduling, input: true);
      expect(out, {'count': 2});
    });

    test('from_question and format round-trip through Field.fromJson / toJson',
        () {
      final field = Field.fromJson({
        'name': 'wake_time',
        'type': {'type': 'string'},
        'from_question': 'q-wake',
        'format': 'time',
      });
      expect(field.fromQuestion, 'q-wake');
      expect(field.format, 'time');
      final json = field.toJson();
      expect(json['from_question'], 'q-wake');
      expect(json['format'], 'time');
      expect(Field.fromJson(json).toJson(), json);
    });

    test('a field without the new keys serialises without them', () {
      final json = Field('x', TypeSpec.integer()).toJson();
      expect(json.containsKey('from_question'), isFalse);
      expect(json.containsKey('format'), isFalse);
      expect(json.keys.toList(), ['name', 'type', 'required', 'nullable']);
      final parsed = Field.fromJson(json);
      expect(parsed.fromQuestion, isNull);
      expect(parsed.format, isNull);
    });

    test('a malformed from_question or format is a path-qualified error', () {
      expect(
        () => Field.fromJson({
          'name': 'x',
          'type': {'type': 'string'},
          'from_question': 42,
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('from_question'))),
      );
      expect(
        () => Schema.fromJson({
          'type': 'object',
          'fields': [
            {
              'name': 'x',
              'type': {'type': 'string'},
              'from_question': 42,
            },
          ],
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('.fields[0]'))
            .having((e) => e.message, 'message', contains('from_question'))),
      );
      expect(
        () => Field.fromJson({
          'name': 'x',
          'type': {'type': 'string'},
          'format': '',
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('format'))),
      );
      expect(
        () => Schema.fromJson({
          'type': 'object',
          'fields': [
            {
              'name': 'x',
              'type': {'type': 'string'},
              'format': '',
            },
          ],
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('.fields[0]'))
            .having((e) => e.message, 'message', contains('format'))),
      );
    });

    test('the validator ignores from_question and format', () {
      final schema = Schema([
        Field('wake_time', TypeSpec.string(),
            fromQuestion: 'q-wake', format: 'time'),
      ]);
      final out = schema.validate({'wake_time': '07:30'},
          part: ScriptKind.scheduling, input: true);
      expect(out, {'wake_time': '07:30'});
      expect(
        () => schema.validate({'wake_time': 730},
            part: ScriptKind.scheduling, input: true),
        throwsA(isA<ScriptError>()
            .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
            .having((e) => e.path, 'path', 'wake_time')),
      );
    });

    test('a settings schema keeps both keys through the server normalisation',
        () {
      // The server normalises a bundle-declared settings schema with
      // Schema.fromJson(raw).toJson(); the keys must survive that pass.
      final schema = Schema([
        Field('wake_time', TypeSpec.string(),
            defaultValue: '07:30',
            description: 'When the day starts.',
            fromQuestion: 'q-wake',
            format: 'time'),
        Field('label', TypeSpec.string()),
      ]);
      final normalised = Schema.fromJson(schema.toJson());
      expect(normalised.toJson(), schema.toJson());
      expect(normalised.fields[0].fromQuestion, 'q-wake');
      expect(normalised.fields[0].format, 'time');
      expect(normalised.fields[1].fromQuestion, isNull);
      expect(normalised.fields[1].format, isNull);
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

  group('participant-editable settings (0.8.0)', () {
    Map<String, Object?> spanType(String partFormat) => {
          'type': 'object',
          'fields': [
            {
              'name': 'start',
              'type': {'type': 'string'},
              'required': true,
              'nullable': false,
              'format': partFormat,
            },
            {
              'name': 'end',
              'type': {'type': 'string'},
              'required': true,
              'nullable': false,
              'format': partFormat,
            },
          ],
        };

    // Key order follows Field.toJson, so jsonEncode can compare bytes.
    Map<String, Object?> editableJson() => {
          'type': 'object',
          'fields': [
            {
              'name': 'daily_prompts',
              'type': {'type': 'int'},
              'required': true,
              'nullable': false,
              'constraint': {'min': 1, 'max': 10},
              'participant_editable': true,
            },
            {
              'name': 'weight',
              'type': {'type': 'double'},
              'required': true,
              'nullable': false,
              'constraint': {'min': 0.5, 'max': 2.5},
              'participant_editable': true,
            },
            {
              'name': 'wake_time',
              'type': {'type': 'string'},
              'required': true,
              'nullable': false,
              'constraint': {'min': '06:00', 'max': '22:00'},
              'format': 'time',
              'participant_editable': true,
            },
            {
              'name': 'start_date',
              'type': {'type': 'string'},
              'required': true,
              'nullable': false,
              'constraint': {'min': '2026-01-01', 'max': '2026-12-31'},
              'format': 'date',
              'participant_editable': true,
            },
            {
              'name': 'quiet_hours',
              'type': spanType('time'),
              'required': true,
              'nullable': false,
              'constraint': {'min': '00:00', 'max': '23:59'},
              'format': 'time_span',
              'participant_editable': true,
            },
            {
              'name': 'holiday',
              'type': spanType('date'),
              'required': true,
              'nullable': false,
              'constraint': {'min': '2026-01-01', 'max': '2026-12-31'},
              'format': 'date_span',
              'participant_editable': true,
            },
          ],
        };

    /// Parse [field] as the only field of a schema and expect a
    /// FormatException whose message contains [message] at [path].
    void expectRejected(Map<String, Object?> field, String message,
        {String path = '.fields[0]'}) {
      expect(
        () => Schema.fromJson({
          'type': 'object',
          'fields': [field],
        }),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('$path: $message'))),
      );
    }

    test('a 0.7.0 descriptor serialises byte-identical', () {
      const v070 = '{"type":"object","fields":['
          '{"name":"count","type":{"type":"int"},"required":true,'
          '"nullable":false,"constraint":{"min":1,"max":10},"default":3,'
          '"description":"How many prompts per day."},'
          '{"name":"ratio","type":{"type":"double"},"required":false,'
          '"nullable":false,"constraint":{"min":0.5,"max":2.5}},'
          '{"name":"label","type":{"type":"string"},"required":true,'
          '"nullable":false,"constraint":{"non_empty":true}},'
          '{"name":"wake_time","type":{"type":"string"},"required":true,'
          '"nullable":false,"from_question":"q-wake","format":"time"},'
          '{"name":"window","type":{"type":"object","fields":['
          '{"name":"start","type":{"type":"timestamp"},"required":true,'
          '"nullable":false},'
          '{"name":"end","type":{"type":"timestamp"},"required":true,'
          '"nullable":false}]},"required":true,"nullable":false}'
          ']}';
      final parsed = Schema.fromJson(jsonDecode(v070));
      expect(jsonEncode(parsed.toJson()), v070);
      for (final field in parsed.fields) {
        expect(field.participantEditable, isFalse);
        expect(field.toJson().containsKey('participant_editable'), isFalse);
      }
    });

    test('the six kinds round-trip and report their editKind', () {
      final json = editableJson();
      final parsed = Schema.fromJson(json);
      expect(jsonEncode(parsed.toJson()), jsonEncode(json));
      expect(parsed.fields.map((f) => f.editKind).toList(), [
        SettingsEditKind.integer,
        SettingsEditKind.decimal,
        SettingsEditKind.time,
        SettingsEditKind.date,
        SettingsEditKind.timeSpan,
        SettingsEditKind.dateSpan,
      ]);
      expect(parsed.fields.every((f) => f.participantEditable), isTrue);
      // The span parts are time and date strings themselves.
      expect(parsed.fields[4].type.fields!.map((f) => f.editKind),
          everyElement(SettingsEditKind.time));
      expect(parsed.fields[5].type.fields!.map((f) => f.editKind),
          everyElement(SettingsEditKind.date));
    });

    test('the typed bound getters return the bound without a cast', () {
      final parsed = Schema.fromJson(editableJson());
      final numeric = parsed.fields[0].constraint!;
      expect(numeric.numMin, 1);
      expect(numeric.numMax, 10);
      expect(numeric.stringMin, isNull);
      expect(numeric.stringMax, isNull);
      final text = parsed.fields[2].constraint!;
      expect(text.stringMin, '06:00');
      expect(text.stringMax, '22:00');
      expect(text.numMin, isNull);
      expect(text.numMax, isNull);
      expect(Constraint.fromJson({'min': '06:00'}).stringMin, '06:00');
    });

    test('SettingsEditKind wire names', () {
      expect(SettingsEditKind.values.map((k) => k.wireName).toList(), [
        'integer',
        'decimal',
        'time',
        'date',
        'time_span',
        'date_span',
      ]);
      for (final kind in SettingsEditKind.values) {
        expect(SettingsEditKind.fromWireName(kind.wireName), kind);
      }
      expect(SettingsEditKind.fromWireName('timeSpan'), isNull);
      expect(SettingsEditKind.fromWireName('bool'), isNull);
    });

    test('editKind is null for the other shapes', () {
      expect(Field('x', TypeSpec.boolean()).editKind, isNull);
      expect(Field('x', TypeSpec.enumeration(['a'])).editKind, isNull);
      expect(Field('x', TypeSpec.timestamp()).editKind, isNull);
      expect(Field('x', TypeSpec.list(TypeSpec.integer())).editKind, isNull);
      expect(Field('x', TypeSpec.map(TypeSpec.integer())).editKind, isNull);
      expect(Field('x', TypeSpec.json()).editKind, isNull);
      expect(Field('x', TypeSpec.string()).editKind, isNull);
      expect(Field('x', TypeSpec.string(), format: 'email').editKind, isNull);
      expect(Field('x', TypeSpec.integer(), format: 'time').editKind,
          SettingsEditKind.integer);
      // A span object without the span format is a plain object.
      final parts = [
        Field('start', TypeSpec.string(), format: Field.formatTime),
        Field('end', TypeSpec.string(), format: Field.formatTime),
      ];
      expect(Field('x', TypeSpec.object(parts)).editKind, isNull);
      expect(
          Field('x', TypeSpec.object(parts), format: Field.formatTimeSpan)
              .editKind,
          SettingsEditKind.timeSpan);
      expect(
          Field('x', TypeSpec.object(parts), format: Field.formatDateSpan)
              .editKind,
          isNull);
    });

    test('a Field built in Dart serialises participant_editable when true', () {
      final json = Field('count', TypeSpec.integer(),
              constraint: const Constraint(min: 1, max: 5),
              participantEditable: true)
          .toJson();
      expect(json['participant_editable'], isTrue);
      expect(Field.fromJson(json).participantEditable, isTrue);
      expect(Field.fromJson(json).toJson(), json);
    });

    test('rejects a malformed bound', () {
      expectRejected({
        'name': 'x',
        'type': {'type': 'int'},
        'constraint': {'min': ''},
      }, '"min" must be a number or a non-empty string',
          path: '.fields[0].constraint');
      expectRejected({
        'name': 'x',
        'type': {'type': 'int'},
        'constraint': {'max': true},
      }, '"max" must be a number or a non-empty string',
          path: '.fields[0].constraint');
    });

    test('rejects a non-bool participant_editable', () {
      expectRejected({
        'name': 'x',
        'type': {'type': 'int'},
        'participant_editable': 'yes',
      }, '"participant_editable" must be a bool');
    });

    test('rejects participant_editable on a field without an edit kind', () {
      const message = 'participant_editable requires one of: integer, '
          'decimal, time, date, time_span, date_span';
      final types = <Map<String, Object?>>[
        {'type': 'bool'},
        {
          'type': 'enum',
          'values': ['a', 'b'],
        },
        {'type': 'timestamp'},
        {
          'type': 'list',
          'element': {'type': 'string'},
        },
        {
          'type': 'map',
          'value': {'type': 'int'},
        },
        {'type': 'json'},
        {'type': 'string'},
        {
          'type': 'object',
          'fields': [
            {
              'name': 'a',
              'type': {'type': 'int'},
            },
          ],
        },
      ];
      for (final type in types) {
        expectRejected({
          'name': 'x',
          'type': type,
          'participant_editable': true,
        }, message);
      }
      // A nested field reports its own path.
      expectRejected({
        'name': 'x',
        'type': {
          'type': 'object',
          'fields': [
            {
              'name': 'flag',
              'type': {'type': 'bool'},
              'participant_editable': true,
            },
          ],
        },
      }, message, path: '.fields[0].type.fields[0]');
    });

    test('rejects a numeric bound on a string-based kind', () {
      expectRejected({
        'name': 'x',
        'type': {'type': 'string'},
        'constraint': {'min': 6},
        'format': 'time',
      }, 'numeric bounds require an int or double field');
      expectRejected({
        'name': 'x',
        'type': spanType('time'),
        'constraint': {'max': 22},
        'format': 'time_span',
      }, 'numeric bounds require an int or double field');
    });

    test('rejects a string bound on a numeric or other type', () {
      const message =
          'string bounds require a time, date, time_span or date_span field';
      expectRejected({
        'name': 'x',
        'type': {'type': 'int'},
        'constraint': {'min': '06:00'},
      }, message);
      expectRejected({
        'name': 'x',
        'type': {'type': 'string'},
        'constraint': {'max': 'z'},
      }, message);
      expectRejected({
        'name': 'x',
        'type': {'type': 'timestamp'},
        'constraint': {'min': '2026-01-01'},
      }, message);
    });

    test('rejects a span format on a shape that is not a span', () {
      const timeMessage = 'format "time_span" requires an object with string '
          'fields start and end (format time)';
      const dateMessage = 'format "date_span" requires an object with string '
          'fields start and end (format date)';
      expectRejected({
        'name': 'x',
        'type': {'type': 'string'},
        'format': 'time_span',
      }, timeMessage);
      expectRejected({
        'name': 'x',
        'type': {
          'type': 'object',
          'fields': [
            {
              'name': 'start',
              'type': {'type': 'string'},
              'format': 'time',
            },
          ],
        },
        'format': 'time_span',
        'participant_editable': true,
      }, timeMessage);
      expectRejected({
        'name': 'x',
        'type': spanType('time'),
        'format': 'date_span',
      }, dateMessage);
    });

    test('format time and date stay advisory on other types', () {
      final parsed = Schema.fromJson({
        'type': 'object',
        'fields': [
          {
            'name': 'x',
            'type': {'type': 'int'},
            'format': 'time',
          },
          {
            'name': 'y',
            'type': {'type': 'bool'},
            'format': 'date',
          },
        ],
      });
      expect(parsed.fields[1].editKind, isNull);
    });

    group('validator', () {
      Schema schema() {
        final fields = <Map<String, Object?>>[
          for (final field in editableJson()['fields'] as List)
            {...(field as Map<String, Object?>), 'required': false},
          {
            'name': 'day_window',
            'type': spanType('time'),
            'required': false,
            'constraint': {'min': '06:00', 'max': '22:00'},
            'format': 'time_span',
            'participant_editable': true,
          },
        ];
        final settings = Schema.fromJson({'type': 'object', 'fields': fields});
        // Nest the settings under `rule` to check the full path.
        return Schema([
          Field('rule', settings.asType),
        ]);
      }

      Map<String, Object?> validate(Map<String, Object?> rule) =>
          schema().validate({'rule': rule},
              part: ScriptKind.scheduling, input: true);

      Matcher fails(String path, String message) => throwsA(isA<ScriptError>()
          .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
          .having((e) => e.path, 'path', path)
          .having((e) => e.message, 'message', message));

      test('a time value outside the string bounds fails', () {
        expect(() => validate({'wake_time': '05:59'}),
            fails('rule.wake_time', 'must be >= 06:00'));
        expect(() => validate({'wake_time': '22:01'}),
            fails('rule.wake_time', 'must be <= 22:00'));
      });

      test('the string bounds are inclusive', () {
        expect(validate({'wake_time': '06:00'})['rule'],
            {'wake_time': '06:00'});
        expect(validate({'wake_time': '22:00'})['rule'],
            {'wake_time': '22:00'});
      });

      test('a date value outside the string bounds fails', () {
        expect(() => validate({'start_date': '2025-12-31'}),
            fails('rule.start_date', 'must be >= 2026-01-01'));
        expect(() => validate({'start_date': '2027-01-01'}),
            fails('rule.start_date', 'must be <= 2026-12-31'));
      });

      test('a span part outside the bounds fails at that part', () {
        expect(
            () => validate({
                  'day_window': {'start': '07:00', 'end': '23:00'},
                }),
            fails('rule.day_window.end', 'must be <= 22:00'));
        expect(
            () => validate({
                  'day_window': {'start': '05:00', 'end': '08:00'},
                }),
            fails('rule.day_window.start', 'must be >= 06:00'));
        expect(
            () => validate({
                  'holiday': {'start': '2026-06-01', 'end': '2027-01-02'},
                }),
            fails('rule.holiday.end', 'must be <= 2026-12-31'));
      });

      test('an overnight time span inside the bounds passes', () {
        final out = validate({
          'quiet_hours': {'start': '22:00', 'end': '06:00'},
        });
        expect(out['rule'], {
          'quiet_hours': {'start': '22:00', 'end': '06:00'},
        });
      });

      test('numeric bounds behave as before', () {
        expect(validate({'daily_prompts': 5})['rule'], {'daily_prompts': 5});
        expect(() => validate({'daily_prompts': 0}),
            fails('rule.daily_prompts', 'must be >= 1'));
        expect(() => validate({'daily_prompts': 11}),
            fails('rule.daily_prompts', 'must be <= 10'));
        expect(() => validate({'weight': 0.25}),
            fails('rule.weight', 'must be >= 0.5'));
        expect(validate({'weight': 2})['rule'], {'weight': 2.0});
      });
    });
  });
}