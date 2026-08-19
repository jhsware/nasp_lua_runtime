import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

const _runtime = LuaScriptRuntime();

Map<String, Object?> _schedulingInput({int horizon = 3}) => {
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
        'rule': {
          'frequency': 'daily',
          'times': ['09:00'],
        },
      },
      'enrolment_date': '2026-01-01T00:00:00Z',
      'now': '2026-06-01T00:00:00Z',
      'horizon_days': horizon,
    };

Map<String, Object?> _qsInput() => {
      'participant_id': 'p1',
      'trigger': {'time': '2026-06-01T09:00:00Z', 'tag': 'morning'},
      'question_sets': [
        {'id': 'set1', 'name': 'Daily', 'state': 'published'},
      ],
      'questions': [
        {
          'id': 'q1',
          'question_set_id': 'set1',
          'type': 'scale',
          'tags': ['mood'],
          'set_position': 1,
        },
        {
          'id': 'q2',
          'question_set_id': 'set1',
          'type': 'scale',
          'tags': ['sleep'],
          'set_position': 2,
        },
      ],
      'answer_history': <Object?>[],
      'seed': 42,
    };

Map<String, Object?> _followUpInput() => {
      'participant_id': 'p1',
      'now': '2026-06-01T09:05:00Z',
      'current_round': {
        'scheduled_at': '2026-06-01T09:00:00Z',
        'answered_at': '2026-06-01T09:05:00Z',
        'delta_seconds': 300,
        'type': 'beep',
        'tag': 'morning',
        'answers': [
          {
            'question_id': 'q1',
            'values': ['3', 'high'],
            'answered_at': '2026-06-01T09:05:00Z',
          },
        ],
      },
      'recent_rounds': [
        {
          'scheduled_at': '2026-05-31T09:00:00Z',
          'answered_at': '2026-05-31T09:02:00Z',
          'delta_seconds': 120,
          'type': 'beep',
          'tag': 'morning',
          'answers': [
            {
              'question_id': 'q1',
              'values': ['2'],
              'answered_at': '2026-05-31T09:02:00Z',
            },
          ],
        },
      ],
      'schedule': [
        {
          'trigger_at': '2026-06-01T09:00:00Z',
          'tag': 'morning',
          'type': 'beep',
          'answered': true,
          'answered_at': '2026-06-01T09:05:00Z',
          'delta_seconds': 300,
        },
        {
          'trigger_at': '2026-06-02T09:00:00Z',
          'tag': 'morning',
          'type': 'beep',
          'answered': false,
        },
      ],
      'seed': 42,
    };

void main() {
  group('scheduling part', () {
    const src = r'''
function schedule(input)
  local out = { triggers = {} }
  local base = input.now
  for i = 0, input.horizon_days - 1 do
    out.triggers[i + 1] = { trigger_at = base + i * 86400, tag = "morning" }
  end
  out.regenerate_after = base + input.horizon_days * 86400
  return out
end
''';

    test('computes tagged triggers over the horizon', () {
      final r = _runtime.run(ScriptKind.scheduling, src, _schedulingInput());
      expect(r.ok, isTrue, reason: r.error?.toString());
      final triggers = r.output!['triggers'] as List;
      expect(triggers.length, 3);
      final base = DateTime.parse('2026-06-01T00:00:00Z');
      expect((triggers[0] as Map)['trigger_at'],
          isA<DateTime>());
      expect(((triggers[0] as Map)['trigger_at'] as DateTime)
          .millisecondsSinceEpoch, base.millisecondsSinceEpoch);
      expect((triggers[0] as Map)['tag'], 'morning');
      expect(((triggers[2] as Map)['trigger_at'] as DateTime)
          .millisecondsSinceEpoch,
          base.add(const Duration(days: 2)).millisecondsSinceEpoch);
      expect((r.output!['regenerate_after'] as DateTime).millisecondsSinceEpoch,
          base.add(const Duration(days: 3)).millisecondsSinceEpoch);
    });

    test('is deterministic across repeat runs', () {
      final a = _runtime.run(ScriptKind.scheduling, src, _schedulingInput());
      final b = _runtime.run(ScriptKind.scheduling, src, _schedulingInput());
      expect(scriptValueToJson(a.output), scriptValueToJson(b.output));
    });

    test('exposes study_length_days to the script when present', () {
      const withLength = r'''
function schedule(input)
  return {
    triggers = {
      { trigger_at = input.now + input.study_length_days * 86400, tag = "end" },
    },
  }
end
''';
      final input = _schedulingInput()..['study_length_days'] = 5;
      final r = _runtime.run(ScriptKind.scheduling, withLength, input);
      expect(r.ok, isTrue, reason: r.error?.toString());
      final t = ((r.output!['triggers'] as List)[0] as Map)['trigger_at']
          as DateTime;
      final base = DateTime.parse('2026-06-01T00:00:00Z');
      expect(t.millisecondsSinceEpoch,
          base.add(const Duration(days: 5)).millisecondsSinceEpoch);
    });
  });

  group('question_selection part', () {
    const src = r'''
function select_questions(input)
  local out = { items = {} }
  for i, q in ipairs(input.questions) do
    out.items[i] = { id = q.id, kind = "question" }
  end
  out.reason = "all in order"
  return out
end
''';

    test('returns ordered items with an enum kind', () {
      final r = _runtime.run(ScriptKind.questionSelection, src, _qsInput());
      expect(r.ok, isTrue, reason: r.error?.toString());
      final items = r.output!['items'] as List;
      expect(items.length, 2);
      expect((items[0] as Map)['id'], 'q1');
      expect((items[0] as Map)['kind'], 'question');
      expect((items[1] as Map)['id'], 'q2');
      expect(r.output!['reason'], 'all in order');
    });

    test('exposes settings.rule to the script when present', () {
      const withSettings = r'''
function select_questions(input)
  local rule = input.settings.rule or {}
  local max = rule.max_questions or #input.questions
  local out = { items = {} }
  for i = 1, max do
    out.items[i] = { id = input.questions[i].id, kind = "question" }
  end
  return out
end
''';
      final input = _qsInput()
        ..['settings'] = {
          'id': 's1',
          'scope': 'participant',
          'participant_id': 'p1',
          'version': 2,
          'state': 'published',
          'rule': {'max_questions': 1},
        };
      final r = _runtime.run(ScriptKind.questionSelection, withSettings, input);
      expect(r.ok, isTrue, reason: r.error?.toString());
      final items = r.output!['items'] as List;
      expect(items.length, 1);
      expect((items[0] as Map)['id'], 'q1');
    });

    test('settings stays optional: an input without it is still valid', () {
      const readsSettings = r'''
function select_questions(input)
  local out = { items = {} }
  if input.settings == nil then
    out.reason = "no settings"
  end
  return out
end
''';
      final r =
          _runtime.run(ScriptKind.questionSelection, readsSettings, _qsInput());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.output!['reason'], 'no settings');
    });
  });

  group('determinism of seeded random()', () {
    const src = r'''
function select_questions(input)
  local out = { items = {} }
  local n = #input.questions
  local pick = random(n)
  out.items[1] = { id = input.questions[pick].id, kind = "question" }
  out.reason = "pick=" .. pick
  return out
end
''';

    test('same seed => identical output', () {
      final a =
          _runtime.run(ScriptKind.questionSelection, src, _qsInput(), seed: 7);
      final b =
          _runtime.run(ScriptKind.questionSelection, src, _qsInput(), seed: 7);
      expect(a.ok && b.ok, isTrue, reason: a.error?.toString());
      expect(scriptValueToJson(a.output), scriptValueToJson(b.output));
    });
  });

  group('error taxonomy', () {
    test('compile error for invalid source', () {
      final r = _runtime.run(
          ScriptKind.scheduling, 'function schedule(input) this is broken',
          _schedulingInput());
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.compile);
    });

    test('inputInvalid before Lua runs', () {
      final bad = _schedulingInput()..remove('timezone');
      final r = _runtime.run(ScriptKind.scheduling, 'function schedule() end',
          bad);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'timezone');
    });

    test('outputInvalid for a wrong-shaped return', () {
      const src = r'''
function schedule(input) return { triggers = "nope" } end
''';
      final r = _runtime.run(ScriptKind.scheduling, src, _schedulingInput());
      expect(r.error!.type, ScriptErrorType.outputInvalid);
      expect(r.error!.path, 'triggers');
    });

    test('runtime error is attributed to the part', () {
      const src = r'''
function schedule(input) error("boom") end
''';
      final r = _runtime.run(ScriptKind.scheduling, src, _schedulingInput());
      expect(r.error!.type, ScriptErrorType.runtime);
      expect(r.error!.part, ScriptKind.scheduling);
    });
  });

  group('sandbox', () {
    test('ambient os is not reachable', () {
      const src = r'''
function schedule(input)
  return { triggers = { { trigger_at = os.time() } } }
end
''';
      final r = _runtime.run(ScriptKind.scheduling, src, _schedulingInput());
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.runtime);
    });

    test('now() returns the host clock, not the wall clock', () {
      const src = r'''
function schedule(input)
  return { triggers = { { trigger_at = now(), tag = "n" } } }
end
''';
      final now = DateTime.parse('2030-03-03T03:03:03Z');
      final r = _runtime.run(ScriptKind.scheduling, src, _schedulingInput(),
          now: now);
      expect(r.ok, isTrue, reason: r.error?.toString());
      final t = ((r.output!['triggers'] as List)[0] as Map)['trigger_at']
          as DateTime;
      expect(t.millisecondsSinceEpoch,
          (now.millisecondsSinceEpoch ~/ 1000) * 1000);
    });
  });

  group('budgets', () {
    test('host-call budget aborts a runaway loop', () {
      const src = r'''
function schedule(input)
  for i = 1, 1000000 do log("x") end
  return { triggers = {} }
end
''';
      final r = _runtime.run(ScriptKind.scheduling, src, _schedulingInput(),
          budget: const RuntimeBudget(maxHostCalls: 50));
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.budgetExceeded);
    });

    test('log() is captured into the trace', () {
      const src = r'''
function schedule(input)
  log("hello")
  log("world")
  return { triggers = {} }
end
''';
      final r = _runtime.run(ScriptKind.scheduling, src, _schedulingInput());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.trace, ['hello', 'world']);
    });
  });

  group('follow_up part', () {
    test('runs, sees answer values, and returns {} for no follow-up', () {
      const src = r'''
function follow_up(input)
  log("value=" .. input.current_round.answers[1].values[1])
  return {}
end
''';
      final r = _runtime.run(ScriptKind.followUp, src, _followUpInput());
      expect(r.ok, isTrue, reason: r.error?.toString());
      expect(r.trace, ['value=3']); // answer values reach the script
      expect(r.output!['follow_up'], isNull); // null/absent => no follow-up
    });
    test('exposes settings.rule to the script when present', () {
      const src = r'''
function follow_up(input)
  local rule = input.settings.rule or {}
  if rule.follow_up_delay_seconds == nil then return {} end
  return { follow_up = {
    trigger_at = input.now + rule.follow_up_delay_seconds,
    tag = "fu",
  } }
end
''';
      final input = _followUpInput()
        ..['settings'] = {
          'id': 's1',
          'scope': 'study',
          'study_id': 'study1',
          'version': 1,
          'state': 'published',
          'rule': {'follow_up_delay_seconds': 600},
        };
      final r = _runtime.run(ScriptKind.followUp, src, input);
      expect(r.ok, isTrue, reason: r.error?.toString());
      final fu = r.output!['follow_up'] as Map;
      final now = DateTime.parse('2026-06-01T09:05:00Z');
      expect((fu['trigger_at'] as DateTime).millisecondsSinceEpoch,
          now.add(const Duration(minutes: 10)).millisecondsSinceEpoch);
    });


    test('returns a follow_up trigger with a typed DateTime', () {
      const src = r'''
function follow_up(input)
  return { follow_up = { trigger_at = input.now + 3600, tag = "followup" } }
end
''';
      final r = _runtime.run(ScriptKind.followUp, src, _followUpInput());
      expect(r.ok, isTrue, reason: r.error?.toString());
      final fu = r.output!['follow_up'] as Map;
      expect(fu['trigger_at'], isA<DateTime>());
      expect(fu['tag'], 'followup');
      final now = DateTime.parse('2026-06-01T09:05:00Z');
      expect((fu['trigger_at'] as DateTime).millisecondsSinceEpoch,
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch);
    });

    test('a follow_up missing trigger_at is outputInvalid', () {
      const src = r'''
function follow_up(input)
  return { follow_up = { tag = "x" } }
end
''';
      final r = _runtime.run(ScriptKind.followUp, src, _followUpInput());
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.outputInvalid);
      expect(r.error!.path, 'follow_up.trigger_at');
    });

    test('input missing current_round is inputInvalid', () {
      final bad = _followUpInput()..remove('current_round');
      final r = _runtime.run(
          ScriptKind.followUp, 'function follow_up(input) end', bad);
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'current_round');
    });

    test('an invalid round type is rejected by the enumeration', () {
      final bad = _followUpInput();
      final round = Map<String, Object?>.from(bad['current_round'] as Map);
      round['type'] = 'other';
      bad['current_round'] = round;
      final r = _runtime.run(
          ScriptKind.followUp, 'function follow_up(input) end', bad);
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'current_round.type');
    });
  });
}
