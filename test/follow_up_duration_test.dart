import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

/// The `follow_up` output of contract v3 (docs/design/time-model.md §3.3):
/// `{trigger_at, tag}` (a clock time) or `{trigger_in_seconds, tag}` (a
/// duration from `now`). Exactly one of the two in a non-null `follow_up`.
void main() {
  const runtime = LuaScriptRuntime();

  ScriptRunResult run(String body) => runtime.run(
    ScriptKind.followUp,
    'function follow_up(input) $body end',
    _input(),
  );

  void expectExactlyOneError(ScriptRunResult r) {
    expect(r.ok, isFalse);
    expect(r.error!.type, ScriptErrorType.outputInvalid);
    expect(r.error!.part, ScriptKind.followUp);
    expect(r.error!.path, 'follow_up');
    expect(
      r.error!.message,
      'exactly one of trigger_at and trigger_in_seconds',
    );
  }

  test('{trigger_in_seconds = 1800, tag = "x"} validates as an int', () {
    final r = run(
      'return { follow_up = { trigger_in_seconds = 1800, tag = "x" } }',
    );
    expect(r.ok, isTrue, reason: '${r.error}');
    final fu = r.output!['follow_up'] as Map;
    expect(fu['trigger_in_seconds'], 1800);
    expect(fu['trigger_in_seconds'], isA<int>());
    expect(fu['trigger_at'], isNull);
    expect(fu['tag'], 'x');
  });

  test('{trigger_at = ..., tag = "x"} validates as a DateTime', () {
    final r = run(
      'return { follow_up = { trigger_at = add_seconds(input.now, 60), '
      'tag = "x" } }',
    );
    expect(r.ok, isTrue, reason: '${r.error}');
    final fu = r.output!['follow_up'] as Map;
    expect(fu['trigger_at'], DateTime.utc(2026, 6, 1, 9, 6));
    expect(fu['trigger_in_seconds'], isNull);
  });

  test('an empty output means no follow-up round', () {
    final r = run('return {}');
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(r.output!['follow_up'], isNull);
  });

  test('a nil follow_up means no follow-up round', () {
    final r = run('return { follow_up = nil }');
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(r.output!['follow_up'], isNull);
  });

  test('both trigger fields are outputInvalid at follow_up', () {
    expectExactlyOneError(
      run(
        'return { follow_up = { trigger_at = input.now, '
        'trigger_in_seconds = 60, tag = "x" } }',
      ),
    );
  });

  test('neither trigger field is outputInvalid at follow_up', () {
    expectExactlyOneError(run('return { follow_up = { tag = "x" } }'));
  });

  test('trigger_in_seconds = 0 is "must be >= 1"', () {
    final r = run(
      'return { follow_up = { trigger_in_seconds = 0, tag = "x" } }',
    );
    expect(r.ok, isFalse);
    expect(r.error!.type, ScriptErrorType.outputInvalid);
    expect(r.error!.path, 'follow_up.trigger_in_seconds');
    expect(r.error!.message, 'must be >= 1');
  });

  test('trigger_in_seconds with a fraction is not an int', () {
    final r = run(
      'return { follow_up = { trigger_in_seconds = 1.5, tag = "x" } }',
    );
    expect(r.ok, isFalse);
    expect(r.error!.type, ScriptErrorType.outputInvalid);
    expect(r.error!.path, 'follow_up.trigger_in_seconds');
  });

  test('the tag stays required', () {
    final r = run('return { follow_up = { trigger_in_seconds = 60 } }');
    expect(r.ok, isFalse);
    expect(r.error!.type, ScriptErrorType.outputInvalid);
    expect(r.error!.path, 'follow_up.tag');
  });
}

Map<String, Object?> _round() => {
  'scheduled_at': '2026-06-01T09:00:00Z',
  'answered_at': '2026-06-01T09:05:00Z',
  'delta_seconds': 300,
  'type': 'beep',
  'tag': 'morning',
  'answers': [
    {
      'question_id': 'q1',
      'values': ['3'],
      'answered_at': '2026-06-01T09:05:00Z',
    },
  ],
};

Map<String, Object?> _input() => {
  'study': <String, Object?>{'zone': 'Europe/Stockholm'},
  'signals': <String, Object?>{
    'participant_id': 'p1',
    'current_round': _round(),
    'recent_rounds': <Object?>[],
    'schedule': <Object?>[],
  },
  'now': '2026-06-01T09:05:00Z',
  'seed': 42,
};
