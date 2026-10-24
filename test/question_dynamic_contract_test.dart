import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

const _runtime = LuaScriptRuntime();

// A valid question_dynamic input (contract version 2): the `question` group,
// the `step` group, the `signals` group and the invocation values `now`,
// `zone` and `seed`. The root question r1 is dynamic and has options; f1 is
// fixed.
Map<String, Object?> _input({int stepIndex = 1}) => {
  'question': <String, Object?>{
    'id': 'bq1',
    'root_question_id': 'r1',
    'questions': <Object?>[
      <String, Object?>{
        'id': 'r1',
        'role': 'root',
        'type': 'multipleChoice',
        'tags': <Object?>['stress'],
        'position': 0,
        'dynamic': true,
        'text': 'How stressed are you?',
        'options': <Object?>[
          <String, Object?>{'label': 'Low', 'value': '1', 'position': 0},
          <String, Object?>{'label': 'High', 'value': '2', 'position': 1},
        ],
      },
      <String, Object?>{
        'id': 'f1',
        'role': 'follow_up',
        'type': 'text',
        'tags': <Object?>['high_stress'],
        'position': 1,
        'dynamic': false,
        'text': 'What is the cause?',
        'options': <Object?>[],
      },
    ],
  },
  'step': <String, Object?>{
    'index': stepIndex,
    'question_ids': stepIndex == 0 ? <Object?>['r1'] : <Object?>['f1'],
  },
  'signals': <String, Object?>{
    'participant_id': 'p1',
    'answers': stepIndex == 0
        ? <Object?>[]
        : <Object?>[
            <String, Object?>{
              'question_id': 'r1',
              'values': <Object?>['2'],
              'answered_at': '2026-06-02T09:05:00.000Z',
            },
          ],
    'earlier_presentations': <Object?>[
      <String, Object?>{
        'schedule_entry_id': 'se1',
        'answered_at': '2026-06-01T09:06:00.000Z',
        'answers': <Object?>[
          <String, Object?>{
            'question_id': 'r1',
            'values': <Object?>['1'],
            'answered_at': '2026-06-01T09:06:00.000Z',
          },
        ],
      },
    ],
  },
  'now': '2026-06-02T09:05:00.000Z',
  'zone': 'Europe/Stockholm',
  'seed': 42,
};

Map<String, Object?> _group(Map<String, Object?> input, String name) =>
    input[name] as Map<String, Object?>;

Map<String, Object?> _member(Map<String, Object?> input, int index) =>
    (_group(input, 'question')['questions'] as List)[index]
        as Map<String, Object?>;

Map<String, Object?> _earlier(Map<String, Object?> input, int index) =>
    (_group(input, 'signals')['earlier_presentations'] as List)[index]
        as Map<String, Object?>;

Map<String, Object?> _validate(Map<String, Object?> input) => contractFor(
  ScriptKind.questionDynamic,
)!.input.validate(input, part: ScriptKind.questionDynamic, input: true);

Matcher _inputInvalidAt(String path) => throwsA(
  isA<ScriptError>()
      .having((e) => e.type, 'type', ScriptErrorType.inputInvalid)
      .having((e) => e.part, 'part', ScriptKind.questionDynamic)
      .having((e) => e.path, 'path', path),
);

void main() {
  group('question_dynamic descriptor', () {
    test('has the entry point, contract version 2 and the field names', () {
      final d = contractFor(ScriptKind.questionDynamic)!;
      expect(d.kind, ScriptKind.questionDynamic);
      expect(d.entrypoint, 'dynamic_questions');
      expect(d.entrypoint, questionDynamicEntrypoint);
      expect(d.ioContractVersion, 2);
      expect(d.ioContractVersion, questionDynamicContractVersion);
      expect(identical(d, questionDynamicContract), isTrue);

      final json = d.toJson();
      expect(json['kind'], 'question_dynamic');
      expect(json['entrypoint'], 'dynamic_questions');
      expect(json['io_contract_version'], 2);
      final inNames = ((json['input'] as Map)['fields'] as List)
          .map((f) => (f as Map)['name'])
          .toList();
      expect(inNames, ['question', 'step', 'signals', 'now', 'zone', 'seed']);
      final outFields = ((json['output'] as Map)['fields'] as List).cast<Map>();
      expect(outFields.map((f) => f['name']).toList(), ['questions', 'reason']);
      for (final f in outFields) {
        expect(f['required'], isFalse, reason: '${f['name']}');
        expect(f['nullable'], isTrue, reason: '${f['name']}');
      }
    });
  });

  group('question_dynamic input validation', () {
    test('a valid input at step 1 with an earlier presentation passes', () {
      final out = _validate(_input());
      expect(_group(out, 'question')['root_question_id'], 'r1');
      expect(_group(out, 'step')['index'], 1);
      expect(_group(out, 'step')['question_ids'], ['f1']);
      expect(_member(out, 0)['dynamic'], isTrue);
      expect(_member(out, 0)['text'], 'How stressed are you?');
      expect((_member(out, 0)['options'] as List).length, 2);
      expect(_member(out, 1)['options'], isEmpty);
      final earlier = _earlier(out, 0);
      expect(earlier['schedule_entry_id'], 'se1');
      expect(earlier['answered_at'], isA<DateTime>());
      expect(out['now'], isA<DateTime>());
      expect(out['seed'], 42);
    });

    test('a valid input at step 0 with no answers passes', () {
      final out = _validate(_input(stepIndex: 0));
      expect(_group(out, 'step')['index'], 0);
      expect(_group(out, 'step')['question_ids'], ['r1']);
      expect(_group(out, 'signals')['answers'], isEmpty);
    });

    test('an empty earlier_presentations list is valid (the first round)', () {
      final input = _input();
      _group(input, 'signals')['earlier_presentations'] = <Object?>[];
      final out = _validate(input);
      expect(_group(out, 'signals')['earlier_presentations'], isEmpty);
    });

    test('an input without step is inputInvalid at `step`', () {
      final bad = _input()..remove('step');
      expect(() => _validate(bad), _inputInvalidAt('step'));
    });

    test('a member without dynamic is inputInvalid at its path', () {
      final bad = _input();
      _member(bad, 0).remove('dynamic');
      expect(
        () => _validate(bad),
        _inputInvalidAt('question.questions[0].dynamic'),
      );
    });

    test('an earlier presentation without answered_at is inputInvalid', () {
      final bad = _input();
      _earlier(bad, 0).remove('answered_at');
      expect(
        () => _validate(bad),
        _inputInvalidAt('signals.earlier_presentations[0].answered_at'),
      );
    });

    test('a signals group without earlier_presentations is inputInvalid', () {
      final bad = _input();
      _group(bad, 'signals').remove('earlier_presentations');
      expect(
        () => _validate(bad),
        _inputInvalidAt('signals.earlier_presentations'),
      );
    });

    test('an empty participant_id is rejected', () {
      final bad = _input();
      _group(bad, 'signals')['participant_id'] = '';
      expect(() => _validate(bad), _inputInvalidAt('signals.participant_id'));
    });
  });

  group('question_dynamic runs', () {
    test('return {} is ok and gives no questions', () {
      final r = _runtime.run(
        ScriptKind.questionDynamic,
        'function dynamic_questions(input) return {} end',
        _input(),
      );
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.output!['questions'], isNull);
      expect(r.output!['reason'], isNull);
    });

    test('returns a rewording with text, options and key', () {
      const src = r'''
function dynamic_questions(input)
  local earlier = input.signals.earlier_presentations
  local last = earlier[#earlier].answers[1].values[1]
  return {
    questions = {
      {
        id = "r1",
        text = "Last time you said " .. last .. ". And now?",
        options = { { label = "Better", value = "1" },
                    { label = "Worse", value = "2" } },
        key = "round2",
      },
    },
    reason = "later round",
  }
end
''';
      final r = _runtime.run(ScriptKind.questionDynamic, src, _input());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.output!['questions'], [
        {
          'id': 'r1',
          'text': 'Last time you said 1. And now?',
          'options': [
            {'label': 'Better', 'value': '1'},
            {'label': 'Worse', 'value': '2'},
          ],
          'key': 'round2',
        },
      ]);
      expect(r.output!['reason'], 'later round');
    });

    test('the script reads the step group', () {
      const src = r'''
function dynamic_questions(input)
  log(input.step.index .. ":" .. input.step.question_ids[1])
  return {}
end
''';
      final r = _runtime.run(
        ScriptKind.questionDynamic,
        src,
        _input(stepIndex: 0),
      );
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.trace, ['0:r1']);
    });

    test('a type key on an item is dropped from the output', () {
      const src = r'''
function dynamic_questions(input)
  return { questions = { { id = "x", type = "likert" } } }
end
''';
      final r = _runtime.run(ScriptKind.questionDynamic, src, _input());
      expect(r.ok, isTrue, reason: r.error?.toString());
      final items = r.output!['questions'] as List;
      expect(items, hasLength(1));
      final item = items.single as Map;
      expect(item['id'], 'x');
      expect(item.containsKey('type'), isFalse);
    });

    test('an item without id is outputInvalid at the path of the item', () {
      const src = r'''
function dynamic_questions(input)
  return { questions = { { text = "x" } } }
end
''';
      final r = _runtime.run(ScriptKind.questionDynamic, src, _input());
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.outputInvalid);
      expect(r.error!.part, ScriptKind.questionDynamic);
      expect(r.error!.path, 'questions[0].id');
    });

    test('an invalid input is rejected before Lua runs', () {
      final bad = _input()..remove('step');
      final r = _runtime.run(
        ScriptKind.questionDynamic,
        'function dynamic_questions(input) return {} end',
        bad,
      );
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'step');
    });
  });

  group('question_dynamic compile', () {
    test('a source with dynamic_questions compiles', () {
      expect(
        _runtime.compile(
          ScriptKind.questionDynamic,
          'function dynamic_questions(input) return {} end',
        ),
        isNull,
      );
    });

    test('a source without dynamic_questions gives the entry point error', () {
      final e = _runtime.compile(
        ScriptKind.questionDynamic,
        'function follow_up_questions(input) return {} end',
      );
      expect(e, isNotNull);
      expect(e!.part, ScriptKind.questionDynamic);
      expect(
        e.message,
        contains("entry point 'dynamic_questions' is not defined"),
      );
    });
  });

  group('ScriptKind', () {
    test('questionDynamic is the last value and resolves from its id', () {
      expect(ScriptKind.values.last, ScriptKind.questionDynamic);
      expect(ScriptKind.values, hasLength(5));
      expect(ScriptKind.questionDynamic.id, 'question_dynamic');
      expect(ScriptKind.fromId('question_dynamic'), ScriptKind.questionDynamic);
    });

    test('bundleParts is unchanged and has no question_dynamic', () {
      expect(ScriptKind.bundleParts, [
        ScriptKind.scheduling,
        ScriptKind.questionSelection,
        ScriptKind.followUp,
      ]);
      expect(
        ScriptKind.bundleParts,
        isNot(contains(ScriptKind.questionDynamic)),
      );
    });
  });
}
