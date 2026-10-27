import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

/// LuaScriptRuntime.declarations (0.15.0, docs/design/mandatory-questions.md
/// §4): a branching script declares with the global `requires_root_answer`
/// that it needs a value for the root question.
void main() {
  const runtime = LuaScriptRuntime();
  const entry = 'function follow_up_questions(input) return {} end';

  ScriptDeclarationsResult followUp(String source) =>
      runtime.declarations(ScriptKind.questionFollowUp, source);

  test('no global is false and no error', () {
    final r = followUp(entry);
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(r.error, isNull);
    expect(r.declarations.requiresRootAnswer, isFalse);
  });

  test('requires_root_answer = true is true', () {
    final r = followUp('requires_root_answer = true\n$entry');
    expect(r.error, isNull);
    expect(r.declarations.requiresRootAnswer, isTrue);
  });

  test('requires_root_answer = false is false', () {
    final r = followUp('requires_root_answer = false\n$entry');
    expect(r.error, isNull);
    expect(r.declarations.requiresRootAnswer, isFalse);
  });

  test('requires_root_answer = nil is false', () {
    final r = followUp('requires_root_answer = nil\n$entry');
    expect(r.error, isNull);
    expect(r.declarations.requiresRootAnswer, isFalse);
  });

  for (final value in const ['1', '"true"', '{}']) {
    test('requires_root_answer = $value is the compile error', () {
      final r = followUp('requires_root_answer = $value\n$entry');
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.compile);
      expect(r.error!.part, ScriptKind.questionFollowUp);
      expect(r.error!.message, 'requires_root_answer must be a boolean');
      expect(r.error!.path, isNull);
      expect(r.declarations.requiresRootAnswer, isFalse);
    });
  }

  test('the global in a question_selection script is false, no error', () {
    final r = runtime.declarations(
      ScriptKind.questionSelection,
      'requires_root_answer = 1\n'
      'function select_questions(input) return { items = {} } end',
    );
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(r.declarations.requiresRootAnswer, isFalse);
  });

  test('a syntax error is the compile error of the chunk', () {
    const source = 'function follow_up_questions(input) return {';
    final r = followUp(source);
    expect(r.ok, isFalse);
    expect(r.error!.type, ScriptErrorType.compile);
    expect(r.error!.part, ScriptKind.questionFollowUp);
    final compiled = runtime.compile(ScriptKind.questionFollowUp, source)!;
    expect(r.error!.type, compiled.type);
    expect(r.error!.message, compiled.message);
    expect(r.declarations.requiresRootAnswer, isFalse);
  });

  test('a chunk without the entry point is the runtime entry-point error', () {
    final r = followUp(
      'requires_root_answer = true\n'
      'function follow_up(input) return {} end',
    );
    expect(r.ok, isFalse);
    expect(r.error!.type, ScriptErrorType.runtime);
    expect(r.error!.part, ScriptKind.questionFollowUp);
    expect(
      r.error!.message,
      "entry point 'follow_up_questions' is not defined",
    );
    expect(r.declarations.requiresRootAnswer, isFalse);
  });

  test('a runtime error in the chunk is the runtime error', () {
    final r = followUp('error("boom")\n$entry');
    expect(r.ok, isFalse);
    expect(r.error!.type, ScriptErrorType.runtime);
    expect(r.error!.message, contains('boom'));
  });

  test('compile ignores the declaration', () {
    expect(
      runtime.compile(
        ScriptKind.questionFollowUp,
        'requires_root_answer = 1\n$entry',
      ),
      isNull,
    );
  });

  test('run ignores the declaration', () {
    final r = runtime.run(
      ScriptKind.questionFollowUp,
      'requires_root_answer = 1\n$entry',
      _input(),
    );
    expect(r.ok, isTrue, reason: '${r.error}');
  });

  test('toJson is the wire shape', () {
    expect(const ScriptDeclarations(requiresRootAnswer: true).toJson(), {
      'requires_root_answer': true,
    });
    expect(const ScriptDeclarations().toJson(), {
      'requires_root_answer': false,
    });
    expect(
      followUp('requires_root_answer = true\n$entry').declarations.toJson(),
      {'requires_root_answer': true},
    );
  });
}

Map<String, Object?> _input() => {
  'question': <String, Object?>{
    'id': 'bq1',
    'root_question_id': 'r1',
    'questions': <Object?>[
      <String, Object?>{
        'id': 'r1',
        'role': 'root',
        'type': 'likert',
        'tags': <Object?>[],
        'position': 0,
      },
    ],
  },
  'signals': <String, Object?>{
    'participant_id': 'p1',
    'answers': <Object?>[
      <String, Object?>{
        'question_id': 'r1',
        'values': <Object?>[],
        'answered_at': '2026-06-01T09:05:00.000Z',
      },
    ],
  },
  'now': '2026-06-01T09:05:00.000Z',
  'zone': 'Europe/Stockholm',
  'seed': 42,
};
