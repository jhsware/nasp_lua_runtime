import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

/// The mandatory fields (0.15.0, docs/design/mandatory-questions.md §3):
/// an optional, nullable boolean `mandatory`, last in its object, on the
/// catalog questions and the items of `question_selection`, on the members
/// and the output questions of `question_follow_up`, and on the members of
/// `question_dynamic`. No contract version moves.
void main() {
  const runtime = LuaScriptRuntime();

  test('the additive change keeps every contract version', () {
    expect(questionSelectionContractVersion, 3);
    expect(questionFollowUpContractVersion, 2);
    expect(questionDynamicContractVersion, 2);
  });

  group('the descriptors', () {
    void expectLastOptionalBool(
      ScriptKind kind,
      String side,
      List<String> path,
      List<String> names,
    ) {
      final json = contractFor(kind)!.toJson();
      final fields = _fieldsAt(json[side] as Map, path);
      expect(fields.map((f) => f['name']).toList(), names);
      final mandatory = fields.last;
      expect(mandatory['name'], 'mandatory');
      expect(mandatory['required'], isFalse);
      expect(mandatory['nullable'], isTrue);
      expect((mandatory['type'] as Map)['type'], 'bool');
      expect(mandatory.containsKey('description'), isFalse);
    }

    test('question_selection study.questions[]: after set_position', () {
      expectLastOptionalBool(
        ScriptKind.questionSelection,
        'input',
        ['study', 'questions'],
        ['id', 'question_set_id', 'type', 'tags', 'set_position', 'mandatory'],
      );
    });

    test('question_selection items[]: after kind', () {
      expectLastOptionalBool(
        ScriptKind.questionSelection,
        'output',
        ['items'],
        ['id', 'kind', 'mandatory'],
      );
    });

    test('question_follow_up question.questions[]: after position', () {
      expectLastOptionalBool(
        ScriptKind.questionFollowUp,
        'input',
        ['question', 'questions'],
        ['id', 'role', 'type', 'tags', 'position', 'mandatory'],
      );
    });

    test('question_follow_up questions[]: after id', () {
      expectLastOptionalBool(
        ScriptKind.questionFollowUp,
        'output',
        ['questions'],
        ['id', 'mandatory'],
      );
    });

    test('question_dynamic question.questions[]: after options', () {
      expectLastOptionalBool(
        ScriptKind.questionDynamic,
        'input',
        ['question', 'questions'],
        [
          'id',
          'role',
          'type',
          'tags',
          'position',
          'dynamic',
          'text',
          'options',
          'mandatory',
        ],
      );
    });

    test('question_dynamic output items have no mandatory', () {
      final json = contractFor(ScriptKind.questionDynamic)!.toJson();
      final fields = _fieldsAt(json['output'] as Map, ['questions']);
      expect(fields.map((f) => f['name']), isNot(contains('mandatory')));
    });
  });

  group('question_selection', () {
    ScriptRunResult run(Map<String, Object?> input, String body) => runtime.run(
      ScriptKind.questionSelection,
      'function select_questions(input) $body end',
      input,
    );

    test('an input without mandatory validates (a 0.14.0 host)', () {
      final r = run(
        _qsInput(),
        'log(tostring(input.study.questions[1].mandatory)) '
        'return { items = {} }',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.trace, ['nil']);
    });

    test('mandatory = true validates and the script reads it', () {
      final r = run(
        _qsInput(mandatory: true),
        'log(tostring(input.study.questions[1].mandatory)) '
        'return { items = {} }',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.trace, ['true']);
    });

    test('mandatory = "yes" is inputInvalid at the path', () {
      final r = run(_qsInput(mandatory: 'yes'), 'return { items = {} }');
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'study.questions[0].mandatory');
    });

    test('an item with mandatory = true comes back with the key', () {
      final r = run(
        _qsInput(),
        'return { items = { { id = "q1", kind = "question", '
        'mandatory = true } } }',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect((r.output!['items'] as List).single, {
        'id': 'q1',
        'kind': 'question',
        'mandatory': true,
      });
    });

    test('an item with mandatory = "yes" is outputInvalid', () {
      final r = run(
        _qsInput(),
        'return { items = { { id = "q1", kind = "question", '
        'mandatory = "yes" } } }',
      );
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.outputInvalid);
      expect(r.error!.path, 'items[0].mandatory');
    });
  });

  group('question_follow_up', () {
    ScriptRunResult run(Map<String, Object?> input, String body) => runtime.run(
      ScriptKind.questionFollowUp,
      'function follow_up_questions(input) $body end',
      input,
    );

    test('an input without mandatory validates (a 0.14.0 host)', () {
      final r = run(
        _fuInput(),
        'log(tostring(input.question.questions[1].mandatory)) return {}',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.trace, ['nil']);
    });

    test('mandatory = true validates and the script reads it', () {
      final r = run(
        _fuInput(mandatory: true),
        'log(tostring(input.question.questions[1].mandatory)) return {}',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.trace, ['true']);
    });

    test('mandatory = "yes" is inputInvalid at the path', () {
      final r = run(_fuInput(mandatory: 'yes'), 'return {}');
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'question.questions[0].mandatory');
    });

    test('a skipped optional root (empty values) is valid', () {
      final r = run(
        _fuInput(rootValues: const []),
        'log(tostring(#input.signals.answers[1].values)) return {}',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.trace, ['0']);
    });

    // A nil nullable output field comes back as null (the marshaller's rule,
    // as for `reason`): an item without mandatory has `mandatory: null`.
    test('a question with mandatory = true comes back with the key', () {
      final r = run(
        _fuInput(),
        'return { questions = { { id = "f1", mandatory = true }, '
        '{ id = "f2" } } }',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.output!['questions'], [
        {'id': 'f1', 'mandatory': true},
        {'id': 'f2', 'mandatory': null},
      ]);
    });

    test('a question with mandatory = "yes" is outputInvalid', () {
      final r = run(
        _fuInput(),
        'return { questions = { { id = "f1", mandatory = "yes" } } }',
      );
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.outputInvalid);
      expect(r.error!.path, 'questions[0].mandatory');
    });
  });

  group('question_dynamic', () {
    ScriptRunResult run(Map<String, Object?> input, String body) => runtime.run(
      ScriptKind.questionDynamic,
      'function dynamic_questions(input) $body end',
      input,
    );

    test('an input without mandatory validates (a 0.14.0 host)', () {
      final r = run(
        _dqInput(),
        'log(tostring(input.question.questions[1].mandatory)) return {}',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.trace, ['nil']);
    });

    test('mandatory = true validates and the script reads it', () {
      final r = run(
        _dqInput(mandatory: true),
        'log(tostring(input.question.questions[1].mandatory)) return {}',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.trace, ['true']);
    });

    test('mandatory = "yes" is inputInvalid at the path', () {
      final r = run(_dqInput(mandatory: 'yes'), 'return {}');
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.inputInvalid);
      expect(r.error!.path, 'question.questions[0].mandatory');
    });
  });
}

/// The fields of the object at [path] in a descriptor node: each segment
/// names a field; a list field is entered through its element.
List<Map> _fieldsAt(Map node, List<String> path) {
  var current = node;
  for (final name in path) {
    final field = (current['fields'] as List).cast<Map>().firstWhere(
      (f) => f['name'] == name,
    );
    current = field['type'] as Map;
    while (current['type'] == 'list') {
      current = current['element'] as Map;
    }
  }
  return (current['fields'] as List).cast<Map>();
}

const Object _absent = Object();

Map<String, Object?> _qsInput({Object? mandatory = _absent}) => {
  'study': <String, Object?>{
    'zone': 'Europe/Stockholm',
    'question_sets': [
      {'id': 'set1', 'name': 'Daily', 'state': 'published'},
    ],
    'questions': [
      {
        'id': 'q1',
        'question_set_id': 'set1',
        'type': 'scale',
        if (!identical(mandatory, _absent)) 'mandatory': mandatory,
      },
    ],
  },
  'signals': <String, Object?>{'participant_id': 'p1', 'answers': <Object?>[]},
  'trigger': <String, Object?>{'time': '2026-06-01T09:00:00Z', 'tag': 'x'},
  'seed': 42,
};

Map<String, Object?> _fuInput({
  Object? mandatory = _absent,
  List<String> rootValues = const ['4'],
}) => {
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
        if (!identical(mandatory, _absent)) 'mandatory': mandatory,
      },
      <String, Object?>{
        'id': 'f1',
        'role': 'follow_up',
        'type': 'text',
        'tags': <Object?>[],
        'position': 1,
      },
    ],
  },
  'signals': <String, Object?>{
    'participant_id': 'p1',
    'answers': <Object?>[
      <String, Object?>{
        'question_id': 'r1',
        'values': <Object?>[...rootValues],
        'answered_at': '2026-06-01T09:05:00.000Z',
      },
    ],
  },
  'now': '2026-06-01T09:05:00.000Z',
  'zone': 'Europe/Stockholm',
  'seed': 42,
};

Map<String, Object?> _dqInput({Object? mandatory = _absent}) => {
  'question': <String, Object?>{
    'id': 'bq1',
    'root_question_id': 'r1',
    'questions': <Object?>[
      <String, Object?>{
        'id': 'r1',
        'role': 'root',
        'type': 'multipleChoice',
        'tags': <Object?>[],
        'position': 0,
        'dynamic': true,
        'text': 'How stressed are you?',
        'options': <Object?>[
          <String, Object?>{'label': 'Low', 'value': '1', 'position': 0},
        ],
        if (!identical(mandatory, _absent)) 'mandatory': mandatory,
      },
    ],
  },
  'step': <String, Object?>{
    'index': 0,
    'question_ids': <Object?>['r1'],
  },
  'signals': <String, Object?>{
    'participant_id': 'p1',
    'answers': <Object?>[],
    'earlier_presentations': <Object?>[],
  },
  'now': '2026-06-02T09:05:00.000Z',
  'zone': 'Europe/Stockholm',
  'seed': 42,
};
