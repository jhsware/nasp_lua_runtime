import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

const _runtime = LuaScriptRuntime();

// A valid question_follow_up input (contract version 1): the `question`
// group, the `signals` group and the invocation values `now` and `seed`.
Map<String, Object?> _input() => {
      'question': <String, Object?>{
        'id': 'bq1',
        'root_question_id': 'r1',
        'questions': <Object?>[
          <String, Object?>{
            'id': 'r1',
            'role': 'root',
            'type': 'likert',
            'tags': <Object?>['stress'],
            'position': 0,
          },
          <String, Object?>{
            'id': 'f1',
            'role': 'follow_up',
            'type': 'text',
            'tags': <Object?>['high_stress'],
            'position': 1,
          },
          <String, Object?>{
            'id': 'f2',
            'role': 'follow_up',
            'type': 'scale',
            'tags': <Object?>[],
            'position': 2,
          },
        ],
      },
      'signals': <String, Object?>{
        'participant_id': 'p1',
        'answers': <Object?>[
          <String, Object?>{
            'question_id': 'r1',
            'values': <Object?>['4'],
            'answered_at': '2026-06-01T09:05:00.000Z',
          },
        ],
      },
      'now': '2026-06-01T09:05:00.000Z',
      'seed': 42,
    };

Map<String, Object?> _group(Map<String, Object?> input, String name) =>
    input[name] as Map<String, Object?>;

Map<String, Object?> _member(Map<String, Object?> input, int index) =>
    (_group(input, 'question')['questions'] as List)[index]
        as Map<String, Object?>;

Map<String, Object?> _answer(Map<String, Object?> input, int index) =>
    (_group(input, 'signals')['answers'] as List)[index]
        as Map<String, Object?>;

Map<String, Object?> _validate(Map<String, Object?> input) =>
    contractFor(ScriptKind.questionFollowUp)!
        .input
        .validate(input, part: ScriptKind.questionFollowUp, input: true);

Matcher _inputInvalidAt(String path) => throwsA(isA<ScriptError>()
    .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
    .having((e) => e.part, 'part', ScriptKind.questionFollowUp)
    .having((e) => e.path, 'path', path));

void main() {
  group('question_follow_up descriptor', () {
    test('has the entry point, contract version 1 and the field names', () {
      final d = contractFor(ScriptKind.questionFollowUp)!;
      expect(d.kind, ScriptKind.questionFollowUp);
      expect(d.entrypoint, 'follow_up_questions');
      expect(d.entrypoint, questionFollowUpEntrypoint);
      expect(d.ioContractVersion, 1);
      expect(d.ioContractVersion, questionFollowUpContractVersion);
      expect(identical(d, questionFollowUpContract), isTrue);

      final json = d.toJson();
      expect(json['kind'], 'question_follow_up');
      expect(json['entrypoint'], 'follow_up_questions');
      expect(json['io_contract_version'], 1);
      final inNames = ((json['input'] as Map)['fields'] as List)
          .map((f) => (f as Map)['name'])
          .toList();
      expect(inNames, ['question', 'signals', 'now', 'seed']);
      final outFields =
          ((json['output'] as Map)['fields'] as List).cast<Map>();
      expect(outFields.map((f) => f['name']).toList(), ['questions', 'reason']);
      for (final f in outFields) {
        expect(f['required'], isFalse, reason: '${f['name']}');
        expect(f['nullable'], isTrue, reason: '${f['name']}');
      }
    });
  });

  group('question_follow_up input validation', () {
    test('a valid input passes', () {
      final out = _validate(_input());
      expect(_group(out, 'question')['root_question_id'], 'r1');
      expect(out['now'], isA<DateTime>());
      expect(out['seed'], 42);
    });

    test('an input without question is inputInvalid at `question`', () {
      final bad = _input()..remove('question');
      expect(() => _validate(bad), _inputInvalidAt('question'));
    });

    test('an input without signals is inputInvalid at `signals`', () {
      final bad = _input()..remove('signals');
      expect(() => _validate(bad), _inputInvalidAt('signals'));
    });

    test('a role that is not root or follow_up is rejected', () {
      final bad = _input();
      _member(bad, 1)['role'] = 'other';
      expect(
          () => _validate(bad), _inputInvalidAt('question.questions[1].role'));
    });

    test('an empty participant_id is rejected', () {
      final bad = _input();
      _group(bad, 'signals')['participant_id'] = '';
      expect(() => _validate(bad), _inputInvalidAt('signals.participant_id'));
    });

    test('an answer with an empty values list is valid (a skipped question)',
        () {
      final input = _input();
      _answer(input, 0)['values'] = <Object?>[];
      final out = _validate(input);
      final answers = _group(out, 'signals')['answers'] as List;
      expect((answers[0] as Map)['values'], isEmpty);
    });
  });

  group('question_follow_up runs', () {
    test('return {} is ok and gives no questions', () {
      final r = _runtime.run(ScriptKind.questionFollowUp,
          'function follow_up_questions(input) return {} end', _input());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.output!['questions'], isNull);
      expect(r.output!['reason'], isNull);
    });

    test('return { questions = {} } is ok', () {
      final r = _runtime.run(
          ScriptKind.questionFollowUp,
          'function follow_up_questions(input) return { questions = {} } end',
          _input());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.output!['questions'], isEmpty);
    });

    test('returns the selected questions and the reason', () {
      const src = r'''
function follow_up_questions(input)
  return { questions = { { id = "f1" } }, reason = "r" }
end
''';
      final r = _runtime.run(ScriptKind.questionFollowUp, src, _input());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.output!['questions'], [
        {'id': 'f1'},
      ]);
      expect(r.output!['reason'], 'r');
    });

    test('the script reads the question group and the answer values', () {
      const src = r'''
function follow_up_questions(input)
  local root = input.question.root_question_id
  local value = input.signals.answers[1].values[1]
  log(root .. "=" .. value)
  if tonumber(value) >= 4 then
    return { questions = { { id = "f1" } } }
  end
  return {}
end
''';
      final r = _runtime.run(ScriptKind.questionFollowUp, src, _input());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.trace, ['r1=4']);
      expect(r.output!['questions'], [
        {'id': 'f1'},
      ]);
    });

    test('an item without id is outputInvalid at the path of the item', () {
      const src = r'''
function follow_up_questions(input)
  return { questions = { { id = "f1" }, { name = "f2" } } }
end
''';
      final r = _runtime.run(ScriptKind.questionFollowUp, src, _input());
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.outputInvalid);
      expect(r.error!.part, ScriptKind.questionFollowUp);
      expect(r.error!.path, 'questions[1].id');
    });

    test('a script that returns nothing is outputInvalid', () {
      final r = _runtime.run(ScriptKind.questionFollowUp,
          'function follow_up_questions(input) end', _input());
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.outputInvalid);
      expect(r.error!.message, contains('expected object'));
    });

    test('an invalid input is rejected before Lua runs', () {
      final bad = _input()..remove('signals');
      final r = _runtime.run(ScriptKind.questionFollowUp,
          'function follow_up_questions(input) return {} end', bad);
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'signals');
    });
  });

  group('question_follow_up compile', () {
    test('a source with follow_up_questions compiles', () {
      expect(
          _runtime.compile(ScriptKind.questionFollowUp,
              'function follow_up_questions(input) return {} end'),
          isNull);
    });

    test('a source without follow_up_questions gives the entry point error',
        () {
      final e = _runtime.compile(ScriptKind.questionFollowUp,
          'function follow_up(input) return {} end');
      expect(e, isNotNull);
      expect(e!.part, ScriptKind.questionFollowUp);
      expect(e.message,
          contains("entry point 'follow_up_questions' is not defined"));
    });
  });

  group('ScriptKind', () {
    test('bundleParts is the three bundle kinds in manifest order', () {
      expect(ScriptKind.bundleParts, [
        ScriptKind.scheduling,
        ScriptKind.questionSelection,
        ScriptKind.followUp,
      ]);
      expect(ScriptKind.bundleParts,
          isNot(contains(ScriptKind.questionFollowUp)));
    });

    test('questionFollowUp is the last value and resolves from its id', () {
      expect(ScriptKind.values.last, ScriptKind.questionFollowUp);
      expect(ScriptKind.questionFollowUp.id, 'question_follow_up');
      expect(ScriptKind.fromId('question_follow_up'),
          ScriptKind.questionFollowUp);
    });
  });
}
