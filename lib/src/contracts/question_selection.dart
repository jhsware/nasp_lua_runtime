/// The `question_selection` kind contract (docs/design/scripting.md §4.3).
///
/// Decide *what* to present at a trigger. Input is the participant id, the
/// trigger's time and tag, the in-scope question sets/questions (ids + light
/// metadata mirroring `nasp_questionnaire`), the recent answer history (ids +
/// timestamps), and a seed for host-provided randomness. Output is the ordered
/// list of question/set ids to present plus an optional `reason`.
library;

import '../errors.dart';
import '../schema.dart';

/// Contract revision (§4.5). Bump only on a breaking change.
const int questionSelectionContractVersion = 1;

/// The global Lua function the runtime invokes:
/// `select_questions(input) -> output`.
const String questionSelectionEntrypoint = 'select_questions';

/// The frozen `question_selection` contract descriptor.
final ContractDescriptor questionSelectionContract = ContractDescriptor(
  kind: ScriptKind.questionSelection,
  entrypoint: questionSelectionEntrypoint,
  ioContractVersion: questionSelectionContractVersion,
  input: Schema([
    Field('participant_id', TypeSpec.string(), constraint: const Constraint(nonEmpty: true)),
    Field('trigger', TypeSpec.object([
      Field('time', TypeSpec.timestamp()),
      Field('tag', TypeSpec.string(), required: false, nullable: true),
    ])),
    Field('question_sets', TypeSpec.list(TypeSpec.object([
      Field('id', TypeSpec.string()),
      Field('name', TypeSpec.string(), required: false, nullable: true),
      Field('state', TypeSpec.string(), required: false, nullable: true),
    ]))),
    Field('questions', TypeSpec.list(TypeSpec.object([
      Field('id', TypeSpec.string()),
      Field('question_set_id', TypeSpec.string(), required: false, nullable: true),
      Field('type', TypeSpec.string(), required: false, nullable: true),
      Field('tags', TypeSpec.list(TypeSpec.string()), required: false),
      Field('set_position', TypeSpec.integer(), required: false, nullable: true),
    ]))),
    Field('answer_history', TypeSpec.list(TypeSpec.object([
      Field('question_id', TypeSpec.string()),
      Field('answered_at', TypeSpec.timestamp()),
    ]))),
    Field('seed', TypeSpec.integer()),
  ]),
  output: Schema([
    Field('items', TypeSpec.list(TypeSpec.object([
      Field('id', TypeSpec.string()),
      Field('kind', TypeSpec.enumeration(['question', 'set'])),
    ]))),
    Field('reason', TypeSpec.string(), required: false, nullable: true),
  ]),
);
