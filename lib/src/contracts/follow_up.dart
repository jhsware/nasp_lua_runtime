/// The `follow_up` kind contract (docs/design/scripting.md §4.3).
///
/// Runs *every time* a participant has answered a round — a regular beep or a
/// follow-up round — and decides whether a follow-up round should be triggered
/// (now or later). Input is the participant id, `now` (the answered round's
/// completion instant; in simulation this equals the trigger time), the
/// just-answered `current_round`, the `recent_rounds` answered in the 24 h
/// before `now` (grouped per round, ordered by `scheduled_at`), the whole
/// session `schedule`, and a `seed` for host-provided randomness. Output is an
/// optional `follow_up` trigger (`trigger_at` + `tag`); a null/absent value
/// means "no follow-up round".
///
/// Unlike every other kind, this input carries answer *values*: the contract-v1
/// "no response values into script inputs" invariant is relaxed for `follow_up`
/// only, so a follow-up decision can react to what was actually answered.
/// `question_selection` keeps its ids+timestamps-only input. See scripting.md
/// §4.3.
library;

import '../errors.dart';
import '../schema.dart';

/// Contract revision (§4.5). Bump only on a breaking change.
const int followUpContractVersion = 1;

/// The global Lua function the runtime invokes: `follow_up(input) -> output`.
const String followUpEntrypoint = 'follow_up';

/// The round kinds a beep can take. A follow-up round can itself be followed
/// up, so both the just-answered `current_round`/`recent_rounds` and the
/// `schedule` entries use this enumeration.
const List<String> _roundTypes = ['beep', 'follow_up'];

/// The shape of one answered round, shared by `current_round` and each item of
/// `recent_rounds`. A round groups the answers a participant gave at one
/// trigger together with the prompt time (`scheduled_at`), the response time
/// (`answered_at`), and the response latency (`delta_seconds`). Each answer
/// carries its `values` — this is the kind whose input includes answer values.
TypeSpec _roundObject() => TypeSpec.object([
      Field('scheduled_at', TypeSpec.timestamp()),
      Field('answered_at', TypeSpec.timestamp()),
      Field('delta_seconds', TypeSpec.integer()),
      Field('type', TypeSpec.enumeration(_roundTypes)),
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
    // The round the participant just answered.
    Field('current_round', _roundObject()),
    // Rounds answered during the 24 h before `now`, grouped per round and
    // ordered by `scheduled_at`.
    Field('recent_rounds', TypeSpec.list(_roundObject())),
    // The whole session timeline, so the script can see what is scheduled and
    // which entries have already been answered.
    Field('schedule', TypeSpec.list(TypeSpec.object([
      Field('trigger_at', TypeSpec.timestamp()),
      Field('tag', TypeSpec.string(), required: false, nullable: true),
      Field('type', TypeSpec.enumeration(_roundTypes)),
      Field('answered', TypeSpec.boolean()),
      Field('answered_at', TypeSpec.timestamp(),
          required: false, nullable: true),
      Field('delta_seconds', TypeSpec.integer(),
          required: false, nullable: true),
    ]))),
    Field('seed', TypeSpec.integer()),
  ]),
  output: Schema([
    // Absent/null => no follow-up round; otherwise the trigger to schedule.
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
