/// The `question_selection` kind contract (docs/design/scripting.md §4.3).
///
/// Decide *what* to present at a trigger. The input is grouped by provenance
/// (contract v2), so the structure itself tells a script author where each
/// value comes from:
///
///  - `study` — study variables, the same for every participant of the study:
///    the in-scope `question_sets` and `questions` (ids + light metadata
///    mirroring `nasp_questionnaire`).
///  - `settings` — the resolved script settings (optional; the server hosts
///    supply it so selection can read `settings.rule`). A participant-scope
///    override wins over the study-scope settings.
///  - `signals` — participant-specific data the script analyses. Today the
///    participant's identity (`participant_id`) and the recent `answers`
///    (ids + timestamps only); later device telemetry such as location and
///    usage (additive). Anything participant-specific is a signal.
///  - top-level — invocation values from the host: the `trigger` (time and
///    tag) and a `seed` for host-provided randomness.
///
/// Output is the ordered list of question/set ids to present plus an optional
/// `reason`.
library;

import '../errors.dart';
import '../schema.dart';
import 'scheduling.dart' show resolvedSettingsSpec;

/// Contract revision (§4.5). Bump only on a breaking change.
///
/// 2 (0.6.0): grouped input — `study` / `settings` / `signals` / invocation
/// values; `answer_history` became `signals.answers`.
const int questionSelectionContractVersion = 2;

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
    Field('study', TypeSpec.object([
      Field('question_sets', TypeSpec.list(TypeSpec.object([
        Field('id', TypeSpec.string()),
        Field('name', TypeSpec.string(), required: false, nullable: true),
        Field('state', TypeSpec.string(), required: false, nullable: true),
      ]))),
      Field('questions', TypeSpec.list(TypeSpec.object([
        Field('id', TypeSpec.string()),
        Field('question_set_id', TypeSpec.string(),
            required: false, nullable: true),
        Field('type', TypeSpec.string(), required: false, nullable: true),
        Field('tags', TypeSpec.list(TypeSpec.string()), required: false),
        Field('set_position', TypeSpec.integer(),
            required: false, nullable: true),
      ]))),
    ])),
    // The resolved script settings (settings.rule = script-specific
    // settings; participant-scope override wins over study scope). Optional —
    // the server hosts always supply it, legacy hosts may omit it.
    Field('settings', resolvedSettingsSpec(), required: false, nullable: true),
    // Participant-specific data the script analyses.
    Field('signals', TypeSpec.object([
      Field('participant_id', TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true)),
      // The recent answer history: ids + timestamps only, never values.
      Field('answers', TypeSpec.list(TypeSpec.object([
        Field('question_id', TypeSpec.string()),
        Field('answered_at', TypeSpec.timestamp()),
      ]))),
    ])),
    // Invocation values from the host.
    Field('trigger', TypeSpec.object([
      Field('time', TypeSpec.timestamp()),
      Field('tag', TypeSpec.string(), required: false, nullable: true),
    ])),
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
