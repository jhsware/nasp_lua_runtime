/// The `question_selection` kind contract (docs/design/scripting.md §4.3).
///
/// Decide *what* to present at a trigger. The input is grouped by provenance
/// (contract v2), so the structure itself tells a script author where each
/// value comes from:
///
///  - `study` — study variables, the same for every participant of the study:
///    the `zone` of the run and the in-scope `question_sets` and `questions`
///    (ids + light metadata mirroring `nasp_questionnaire`).
///  - `settings` — the resolved script settings (optional; the server hosts
///    supply it so selection can read `settings.rule`). A participant-scope
///    override wins over the study-scope settings.
///  - `signals` — participant-specific data the script analyses. Today the
///    participant's identity (`participant_id`) and the recent `answers`
///    (ids + timestamps only); later device telemetry such as location and
///    usage (additive). Anything participant-specific is a signal.
///  - top-level — invocation values from the host: the `trigger` (time, tag
///    and type) and a `seed` for host-provided randomness. The tag is chosen
///    by the scheduling script; the type is the round type set by the host:
///    `beep`, `follow_up`, or `participant` for a round the participant
///    started on their own (a self check-in). The type is optional.
///
/// Every timestamp is local epoch seconds in the zone of the run (contract
/// v3, docs/design/time-model.md).
///
/// Output is the ordered list of question/set ids to present plus an optional
/// `reason`.
library;

import '../errors.dart';
import '../schema.dart';
import 'round_types.dart';
import 'scheduling.dart' show resolvedSettingsSpec;

/// Contract revision (§4.5). Bump only on a breaking change.
///
/// 2 (0.6.0): grouped input — `study` / `settings` / `signals` / invocation
/// values; `answer_history` became `signals.answers`.
/// 3 (0.13.0): every timestamp is local epoch seconds in the zone of the run;
/// `study.zone` added (required).
/// 0.14.0 added the optional `trigger.type` (additive, still 3).
/// 0.15.0 added the optional `mandatory` on the catalog questions and the
/// items (additive, still 3).
const int questionSelectionContractVersion = 3;

/// The global Lua function the runtime invokes:
/// `select_questions(input) -> output`.
const String questionSelectionEntrypoint = 'select_questions';

/// The frozen `question_selection` contract descriptor.
final ContractDescriptor questionSelectionContract = ContractDescriptor(
  kind: ScriptKind.questionSelection,
  entrypoint: questionSelectionEntrypoint,
  ioContractVersion: questionSelectionContractVersion,
  input: Schema([
    // Study variables — the same for every participant of the study.
    Field(
      'study',
      TypeSpec.object([
        // The IANA zone this run resolves local times in.
        Field(
          'zone',
          TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true),
        ),
        Field(
          'question_sets',
          TypeSpec.list(
            TypeSpec.object([
              Field('id', TypeSpec.string()),
              Field('name', TypeSpec.string(), required: false, nullable: true),
              Field(
                'state',
                TypeSpec.string(),
                required: false,
                nullable: true,
              ),
            ]),
          ),
        ),
        Field(
          'questions',
          TypeSpec.list(
            TypeSpec.object([
              Field('id', TypeSpec.string()),
              Field(
                'question_set_id',
                TypeSpec.string(),
                required: false,
                nullable: true,
              ),
              Field('type', TypeSpec.string(), required: false, nullable: true),
              Field('tags', TypeSpec.list(TypeSpec.string()), required: false),
              Field(
                'set_position',
                TypeSpec.integer(),
                required: false,
                nullable: true,
              ),
              // The effective setting of the question. Absent from a host
              // older than 0.15.0.
              Field(
                'mandatory',
                TypeSpec.boolean(),
                required: false,
                nullable: true,
              ),
            ]),
          ),
        ),
      ]),
    ),
    // The resolved script settings (settings.rule = script-specific
    // settings; participant-scope override wins over study scope). Optional —
    // the server hosts always supply it, legacy hosts may omit it.
    Field('settings', resolvedSettingsSpec(), required: false, nullable: true),
    // Participant-specific data the script analyses.
    Field(
      'signals',
      TypeSpec.object([
        Field(
          'participant_id',
          TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true),
        ),
        // The recent answer history: ids + timestamps only, never values.
        // answered_at is local epoch seconds in the zone of the run.
        Field(
          'answers',
          TypeSpec.list(
            TypeSpec.object([
              Field('question_id', TypeSpec.string()),
              Field('answered_at', TypeSpec.timestamp()),
            ]),
          ),
        ),
      ]),
    ),
    // Invocation values from the host. trigger.time is local epoch seconds
    // in the zone of the run. trigger.tag is chosen by the scheduling script;
    // trigger.type is the round type set by the host (roundTypes: `beep`,
    // `follow_up`, or `participant` for a self check-in). Optional: a host
    // older than 0.14.0 sends no type.
    Field(
      'trigger',
      TypeSpec.object([
        Field('time', TypeSpec.timestamp()),
        Field('tag', TypeSpec.string(), required: false, nullable: true),
        Field(
          'type',
          TypeSpec.enumeration(roundTypes),
          required: false,
          nullable: true,
        ),
      ]),
    ),
    Field('seed', TypeSpec.integer()),
  ]),
  output: Schema([
    Field(
      'items',
      TypeSpec.list(
        TypeSpec.object([
          Field('id', TypeSpec.string()),
          Field('kind', TypeSpec.enumeration(['question', 'set'])),
          // true makes the item mandatory in this round (a question, every
          // member of a set, or the root of a branched question). false or
          // absent leaves the effective setting.
          Field(
            'mandatory',
            TypeSpec.boolean(),
            required: false,
            nullable: true,
          ),
        ]),
      ),
    ),
    Field('reason', TypeSpec.string(), required: false, nullable: true),
  ]),
);
