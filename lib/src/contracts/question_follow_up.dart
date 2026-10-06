/// The `question_follow_up` kind contract
/// (nasp_waves_server docs/design/branched-questions.md §6).
///
/// The script of a branched question. It decides which follow-up questions
/// of the branched question to ask next. The host runs it after the
/// participant answers the root question, and again after each group of
/// follow-up answers. The presentation is complete when the script selects
/// no new question. This kind is never a part of a script bundle (see
/// [ScriptKind.bundleParts]).
///
/// The input is grouped by provenance, as for the bundle kinds:
///
///  - `question` — the branched question at the version that the participant
///    gets: its `id`, the `root_question_id` and all member `questions`
///    (`id`, `role`, `type`, `tags`, `position`). It is the same for each
///    participant.
///  - `signals` — data about this participant: the `participant_id` and the
///    `answers` of this presentation, in answer order. In Lua, `answers[1]` is
///    the answer to the root question.
///  - top-level — invocation values from the host: `now` (the `answered_at`
///    of the last answer) and a `seed` for host-provided randomness.
///
/// There is no `study`, `settings` or `trigger` group in contract version 1.
/// A branched question is in the question bank, and more than one study can
/// use it. Adding an optional field later is additive.
///
/// As for the `follow_up` kind, this input carries answer *values*: the
/// script cannot decide without them. A skipped question has an empty
/// `values` list. The output contains only question ids: an optional,
/// ordered `questions` list and an optional `reason`. An absent, null or
/// empty `questions` list means "the presentation is complete".
library;

import '../errors.dart';
import '../schema.dart';

/// Contract revision (§4.5). Bump only on a breaking change.
///
/// 1 (0.10.0): `question` / `signals` / invocation values.
const int questionFollowUpContractVersion = 1;

/// The global Lua function the runtime invokes:
/// `follow_up_questions(input) -> output`.
const String questionFollowUpEntrypoint = 'follow_up_questions';

/// The roles a member question of a branched question can have.
const List<String> _memberRoles = ['root', 'follow_up'];

/// The frozen `question_follow_up` contract descriptor.
final ContractDescriptor questionFollowUpContract = ContractDescriptor(
  kind: ScriptKind.questionFollowUp,
  entrypoint: questionFollowUpEntrypoint,
  ioContractVersion: questionFollowUpContractVersion,
  input: Schema([
    // The branched question at the version that the participant gets. It is
    // the same for each participant.
    Field('question', TypeSpec.object([
      Field('id', TypeSpec.string()),
      Field('root_question_id', TypeSpec.string()),
      // All members at that version, ordered by position.
      Field('questions', TypeSpec.list(TypeSpec.object([
        Field('id', TypeSpec.string()),
        Field('role', TypeSpec.enumeration(_memberRoles)),
        Field('type', TypeSpec.string()),
        Field('tags', TypeSpec.list(TypeSpec.string())),
        Field('position', TypeSpec.integer()),
      ]))),
    ])),
    // Data about this participant.
    Field('signals', TypeSpec.object([
      Field('participant_id', TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true)),
      // The answers of this presentation, in answer order. The values list is
      // empty when the participant skipped the question.
      Field('answers', TypeSpec.list(TypeSpec.object([
        Field('question_id', TypeSpec.string()),
        Field('values', TypeSpec.list(TypeSpec.string())),
        Field('answered_at', TypeSpec.timestamp()),
      ]))),
    ])),
    // Invocation values from the host: the answered_at of the last answer and
    // the seed.
    Field('now', TypeSpec.timestamp()),
    Field('seed', TypeSpec.integer()),
  ]),
  output: Schema([
    // The follow-up questions to ask next, in this order. Absent, null or
    // empty => the presentation is complete.
    Field(
      'questions',
      TypeSpec.list(TypeSpec.object([
        Field('id', TypeSpec.string()),
      ])),
      required: false,
      nullable: true,
    ),
    Field('reason', TypeSpec.string(), required: false, nullable: true),
  ]),
);
