import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

/// The round type (0.14.0): `participant` is a round type of `follow_up`
/// wherever a round type appears, and `question_selection` takes an optional
/// `trigger.type` with the same enumeration. Both contracts keep version 3.
void main() {
  const runtime = LuaScriptRuntime();

  test('roundTypes is beep, follow_up, participant', () {
    expect(roundTypes, ['beep', 'follow_up', 'participant']);
    expect(roundTypes, [
      roundTypeBeep,
      roundTypeFollowUp,
      roundTypeParticipant,
    ]);
  });

  test('the additive change keeps both contract versions at 3', () {
    expect(followUpContractVersion, 3);
    expect(questionSelectionContractVersion, 3);
  });

  group('follow_up', () {
    ScriptRunResult run(Map<String, Object?> input, [String? body]) =>
        runtime.run(
          ScriptKind.followUp,
          'function follow_up(input) ${body ?? 'return {}'} end',
          input,
        );

    test('participant validates in current_round, recent_rounds and '
        'schedule, and the script reads it', () {
      final r = run(
        _followUpInput(
          currentType: 'participant',
          recentType: 'participant',
          scheduleType: 'participant',
        ),
        'if input.signals.current_round.type == "participant" '
        'and input.signals.recent_rounds[1].type == "participant" '
        'and input.signals.schedule[2].type == "participant" then '
        'return { follow_up = { trigger_in_seconds = 600, '
        'tag = "after_self" } } end return {}',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      final fu = r.output!['follow_up'] as Map;
      expect(fu['tag'], 'after_self');
      expect(fu['trigger_in_seconds'], 600);
    });

    test('a beep round still validates and is told apart', () {
      final r = run(
        _followUpInput(),
        'if input.signals.current_round.type == "participant" then '
        'return { follow_up = { trigger_in_seconds = 600, tag = "x" } } '
        'end return {}',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.output!['follow_up'], isNull);
    });

    test('an unknown type in current_round is inputInvalid', () {
      final r = run(_followUpInput(currentType: 'other'));
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'signals.current_round.type');
    });

    test('an unknown type in recent_rounds is inputInvalid', () {
      final r = run(_followUpInput(recentType: 'other'));
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'signals.recent_rounds[0].type');
    });

    test('an unknown type in schedule is inputInvalid', () {
      final r = run(_followUpInput(scheduleType: 'other'));
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'signals.schedule[1].type');
    });
  });

  group('question_selection trigger.type', () {
    ScriptRunResult run(Map<String, Object?> input, String body) => runtime.run(
      ScriptKind.questionSelection,
      'function select_questions(input) $body end',
      input,
    );

    test('an input without trigger.type validates (backward compatible)', () {
      final r = run(
        _qsInput(),
        'if input.trigger.type == nil then '
        'return { items = { { id = "q1", kind = "question" } } } end '
        'return { items = {} }',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.output!['items'], hasLength(1));
    });

    test('a null trigger.type validates', () {
      final r = run(
        _qsInput(type: null, withType: true),
        'return { items = {} }',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
    });

    for (final type in roundTypes) {
      test('trigger.type = $type validates and the script reads it', () {
        final r = run(
          _qsInput(type: type, withType: true),
          'return { items = {}, reason = input.trigger.type }',
        );
        expect(r.ok, isTrue, reason: '${r.error}');
        expect(r.output!['reason'], type);
      });
    }

    test('a participant round can pick its own questions', () {
      final r = run(
        _qsInput(type: 'participant', withType: true, tag: 'participant'),
        'if input.trigger.type == "participant" then '
        'return { items = { { id = "q2", kind = "question" } } } end '
        'return { items = { { id = "q1", kind = "question" } } }',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect((r.output!['items'] as List).single, {
        'id': 'q2',
        'kind': 'question',
      });
    });

    test('an unknown trigger.type is inputInvalid at trigger.type', () {
      final r = run(
        _qsInput(type: 'other', withType: true),
        'return { items = {} }',
      );
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'trigger.type');
    });

    test('the descriptor lists trigger.type as an optional enumeration', () {
      final json = contractFor(ScriptKind.questionSelection)!.toJson();
      final trigger = ((json['input'] as Map)['fields'] as List)
          .cast<Map>()
          .firstWhere((f) => f['name'] == 'trigger');
      final type = ((trigger['type'] as Map)['fields'] as List)
          .cast<Map>()
          .firstWhere((f) => f['name'] == 'type');
      expect(type['required'], isFalse);
      expect(type['nullable'], isTrue);
      expect((type['type'] as Map)['values'], roundTypes);
    });
  });
}

Map<String, Object?> _round(String type) => {
  'scheduled_at': '2026-06-01T09:00:00Z',
  'answered_at': '2026-06-01T09:05:00Z',
  'delta_seconds': 300,
  'type': type,
  'tag': type == 'participant' ? 'participant' : 'morning',
  'answers': [
    {
      'question_id': 'q1',
      'values': ['3'],
      'answered_at': '2026-06-01T09:05:00Z',
    },
  ],
};

Map<String, Object?> _followUpInput({
  String currentType = 'beep',
  String recentType = 'beep',
  String scheduleType = 'beep',
}) => {
  'study': <String, Object?>{'zone': 'Europe/Stockholm'},
  'signals': <String, Object?>{
    'participant_id': 'p1',
    'current_round': _round(currentType),
    'recent_rounds': [_round(recentType)],
    'schedule': [
      {
        'trigger_at': '2026-06-01T08:00:00Z',
        'tag': 'morning',
        'type': 'beep',
        'answered': true,
        'answered_at': '2026-06-01T08:03:00Z',
        'delta_seconds': 180,
      },
      {
        'trigger_at': '2026-06-01T09:00:00Z',
        'tag': 'participant',
        'type': scheduleType,
        'answered': true,
        'answered_at': '2026-06-01T09:05:00Z',
        'delta_seconds': 300,
      },
    ],
  },
  'now': '2026-06-01T09:05:00Z',
  'seed': 42,
};

Map<String, Object?> _qsInput({
  String? type,
  bool withType = false,
  String tag = 'morning',
}) => {
  'study': <String, Object?>{
    'zone': 'Europe/Stockholm',
    'question_sets': [
      {'id': 'set1', 'name': 'Daily', 'state': 'published'},
    ],
    'questions': [
      {'id': 'q1', 'question_set_id': 'set1', 'type': 'scale'},
      {'id': 'q2', 'question_set_id': 'set1', 'type': 'scale'},
    ],
  },
  'signals': <String, Object?>{'participant_id': 'p1', 'answers': <Object?>[]},
  'trigger': <String, Object?>{
    'time': '2026-06-01T09:00:00Z',
    'tag': tag,
    if (withType) 'type': type,
  },
  'seed': 42,
};
