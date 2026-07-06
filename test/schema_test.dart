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
}
