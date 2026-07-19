/// The `follow_up` kind contract (docs/design/scripting.md §4.3).
///
/// Decide *whether an answered round triggers a follow-up round* — now or
/// later. Unlike `scheduling` (when to prompt) and `question_selection` (what
/// to ask), this part runs **every time a participant answers a round** — a
/// regular beep or an earlier follow-up round — with `now` set to that round's
/// completion instant (in simulation this equals the trigger time). Input is
/// the participant id, the round just answered (`current_round`), the rounds
/// answered during the 24 h before `now` (`recent_rounds`, grouped per round
/// and ordered by `scheduled_at`), the whole session timeline (`schedule`), and
/// a seed for host-provided randomness.
///
/// This is the **only** kind whose input carries answer *values*: each round's
/// `answers` list holds the selected values per question, so a follow-up can
/// branch on what was actually answered. The contract-v1 "no response values
/// into script inputs" invariant is deliberately relaxed for this kind alone —
/// `question_selection` still receives ids + timestamps only (scripting.md
/// §4.3).
///
/// Output is a single optional `follow_up` object `{trigger_at, tag}`;
/// null/absent means "no follow-up round".
library;

import '../errors.dart';
import '../schema.dart';

/// Contract revision (§4.5). Bump only on a breaking change.
const int followUpContractVersion = 1;

/// The global Lua function the runtime invokes: `follow_up(input) -> output`.
const String followUpEntrypoint = 'follow_up';

/// The round object shared by `current_round` and each `recent_rounds` item:
/// when the round was scheduled and answered, the response delay, the round
/// type, an optional tag, and the per-question `answers` — the only place
/// answer values enter a script input (see the library doc comment).
TypeSpec _roundObject() => TypeSpec.object([
      Field('scheduled_at', TypeSpec.timestamp()),
      Field('answered_at', TypeSpec.timestamp()),
      Field('delta_seconds', TypeSpec.integer()),
      Field('type', TypeSpec.enumeration(['beep', 'follow_up'])),
      Field('tag', TypeSpec.string(), required: false, nullable: true),
      Field('answers', TypeSpec.list(TypeSpec.object([
        Field('question_id', TypeSpec.string()),
        Field('values', TypeSpec.list(TypeSpec.string())),
        Field('answered_at', TypeSpec.timestamp()),
      ]))),
    ]);

/// The frozen `follow_up` contract descriptor.
final ContractDescriptor followUpContract = ContractDescriptor(
  kind: ScriptKind.followUp,
  entrypoint: followUpEntrypoint,
  ioContractVersion: followUpContractVersion,
  input: Schema([
    Field('participant_id', TypeSpec.string(),
        constraint: const Constraint(nonEmpty: true)),
    // The answered round's completion instant; in simulation this equals the
    // trigger time.
    Field('now', TypeSpec.timestamp()),
    // The round just answered.
    Field('current_round', _roundObject()),
    // Rounds answered during the 24 h before `now`, grouped per round and
    // ordered by `scheduled_at`.
    Field('recent_rounds', TypeSpec.list(_roundObject())),
    // The whole session timeline.
    Field('schedule', TypeSpec.list(TypeSpec.object([
      Field('trigger_at', TypeSpec.timestamp()),
      Field('tag', TypeSpec.string(), required: false, nullable: true),
      Field('type', TypeSpec.enumeration(['beep', 'follow_up'])),
      Field('answered', TypeSpec.boolean()),
      Field('answered_at', TypeSpec.timestamp(),
          required: false, nullable: true),
      Field('delta_seconds', TypeSpec.integer(),
          required: false, nullable: true),
    ]))),
    Field('seed', TypeSpec.integer()),
  ]),
  output: Schema([
    // null/absent means "no follow-up round".
    Field(
      'follow_up',
      TypeSpec.object([
        Field('trigger_at', TypeSpec.timestamp()),
        Field('tag', TypeSpec.string()),
      ]),
      required: false,
      nullable: true,
    ),
  ]),
);
