/// The `question_dynamic` kind contract
/// (nasp_waves_server docs/design/dynamic-questions.md §6).
///
/// The dynamic questions script of a branched question. It decides the text
/// and the options of the dynamic members for one step of a presentation.
/// The host runs it at step 0, before the root question, and again after
/// each branching step, before it presents the questions of that step. This
/// kind is never a part of a script bundle (see [ScriptKind.bundleParts]).
///
/// The input is grouped by provenance, as for the other kinds:
///
///  - `question` — the branched question at the version that the participant
///    gets: its `id`, the `root_question_id` and all member `questions`
///    (`id`, `role`, `type`, `tags`, `position`, `dynamic`, the base `text`
///    and the base `options`). It is the same for each participant.
///  - `step` — the step that the host runs now: the `index` (0 before the
///    root question, then the number of branching steps that ran before this
///    step) and the `question_ids` that the host presents in this step, in
///    order. Fixed and dynamic questions are both in the list.
///  - `signals` — data about this participant: the `participant_id`, the
///    `answers` of this presentation in answer order (empty at step 0), and
///    the `earlier_presentations` of this branched question by this
///    participant, oldest first (empty in the first round).
///  - top-level — invocation values from the host: `now` and a `seed` for
///    host-provided randomness.
///
/// There is no `study`, `settings` or `trigger` group and no `type_config`
/// in contract version 1. Adding an optional field later is additive.
///
/// The output is an optional `questions` list with one item for each question
/// to change (`id`, and optional `text`, `options` and `key`) and an optional
/// `reason`. An absent, null or empty `questions` list means "each question
/// of the step keeps its base content". An option in the output has no
/// `position`: the host gives each option its index in the list. The output
/// has no `type` and no `type_config` field. The validator drops a key that
/// the schema does not declare, so a script that returns one changes nothing.
library;

import '../errors.dart';
import '../schema.dart';

/// Contract revision (§4.5). Bump only on a breaking change.
///
/// 1 (0.11.0): `question` / `step` / `signals` / invocation values.
const int questionDynamicContractVersion = 1;

/// The global Lua function the runtime invokes:
/// `dynamic_questions(input) -> output`.
const String questionDynamicEntrypoint = 'dynamic_questions';

/// The roles a member question of a branched question can have.
const List<String> _memberRoles = ['root', 'follow_up'];

/// One answer of a presentation: the same shape as in `question_follow_up`.
TypeSpec _answer() => TypeSpec.object([
  Field('question_id', TypeSpec.string()),
  Field('values', TypeSpec.list(TypeSpec.string())),
  Field('answered_at', TypeSpec.timestamp()),
]);

/// The frozen `question_dynamic` contract descriptor.
final ContractDescriptor questionDynamicContract = ContractDescriptor(
  kind: ScriptKind.questionDynamic,
  entrypoint: questionDynamicEntrypoint,
  ioContractVersion: questionDynamicContractVersion,
  input: Schema([
    // The branched question at the version that the participant gets. It is
    // the same for each participant.
    Field(
      'question',
      TypeSpec.object([
        Field('id', TypeSpec.string()),
        Field('root_question_id', TypeSpec.string()),
        // All members at that version, ordered by position.
        Field(
          'questions',
          TypeSpec.list(
            TypeSpec.object([
              Field('id', TypeSpec.string()),
              Field('role', TypeSpec.enumeration(_memberRoles)),
              Field('type', TypeSpec.string()),
              Field('tags', TypeSpec.list(TypeSpec.string())),
              Field('position', TypeSpec.integer()),
              Field('dynamic', TypeSpec.boolean()),
              // The base text and the base options, ordered by position. The
              // options list is empty for a type without options.
              Field('text', TypeSpec.string()),
              Field(
                'options',
                TypeSpec.list(
                  TypeSpec.object([
                    Field('label', TypeSpec.string()),
                    Field('value', TypeSpec.string()),
                    Field('position', TypeSpec.integer()),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    ),
    // The step of the presentation that the host runs now.
    Field(
      'step',
      TypeSpec.object([
        Field('index', TypeSpec.integer()),
        Field('question_ids', TypeSpec.list(TypeSpec.string())),
      ]),
    ),
    // Data about this participant.
    Field(
      'signals',
      TypeSpec.object([
        Field(
          'participant_id',
          TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true),
        ),
        // The answers of this presentation, in answer order. Empty at step 0.
        // The values list is empty when the participant skipped the question.
        Field('answers', TypeSpec.list(_answer())),
        // The earlier presentations of this branched question by this
        // participant, oldest first. Empty in the first round.
        Field(
          'earlier_presentations',
          TypeSpec.list(
            TypeSpec.object([
              Field('schedule_entry_id', TypeSpec.string()),
              Field('answered_at', TypeSpec.timestamp()),
              Field('answers', TypeSpec.list(_answer())),
            ]),
          ),
        ),
      ]),
    ),
    // Invocation values from the host.
    Field('now', TypeSpec.timestamp()),
    Field('seed', TypeSpec.integer()),
  ]),
  output: Schema([
    // One item for each question to change. Absent, null or empty => each
    // question of the step keeps its base content.
    Field(
      'questions',
      TypeSpec.list(
        TypeSpec.object([
          Field('id', TypeSpec.string()),
          Field('text', TypeSpec.string(), required: false, nullable: true),
          // The options to present, in order. No position: the host gives
          // each option its index in the list.
          Field(
            'options',
            TypeSpec.list(
              TypeSpec.object([
                Field('label', TypeSpec.string()),
                Field('value', TypeSpec.string()),
              ]),
            ),
            required: false,
            nullable: true,
          ),
          Field('key', TypeSpec.string(), required: false, nullable: true),
        ]),
      ),
      required: false,
      nullable: true,
    ),
    Field('reason', TypeSpec.string(), required: false, nullable: true),
  ]),
);
