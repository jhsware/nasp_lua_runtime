/// The `follow_up` kind contract (docs/design/scripting.md §4.3).
///
/// Runs *every time* a participant has answered a round — a regular beep, a
/// follow-up round, or a round the participant started on their own (a self
/// check-in, round type `participant`) — and decides whether a follow-up
/// round should be triggered (now or later). The input is grouped by
/// provenance (contract v2), so the structure itself tells a script author
/// where each value comes from:
///
///  - `study` — study variables: the `zone` of the run (contract v3).
///  - `settings` — the resolved script settings (optional; the server hosts
///    supply it so a follow-up decision can read `settings.rule`). A
///    participant-scope override wins over the study-scope settings.
///  - `signals` — participant-specific data the script analyses. Today the
///    participant's identity (`participant_id`), the just-answered
///    `current_round`, the `recent_rounds` answered in the 24 h before `now`
///    (grouped per round, ordered by `scheduled_at`) and the whole session
///    `schedule`; later device telemetry such as location and usage
///    (additive). Anything participant-specific is a signal.
///  - top-level — invocation values from the host: `now` (the answered
///    round's completion time; in simulation this equals the trigger time)
///    and a `seed` for host-provided randomness.
///
/// Every timestamp is local epoch seconds in the zone of the run (contract
/// v3, docs/design/time-model.md).
///
/// Output is an optional `follow_up` trigger: `{trigger_at, tag}` (a clock
/// time, local epoch seconds) or `{trigger_in_seconds, tag}` (a duration
/// from `now` on the time line; the host adds it to the instant of `now`).
/// Exactly one of `trigger_at` and `trigger_in_seconds`. A null/absent value
/// means "no follow-up round".
///
/// Unlike every other kind, this input carries answer *values*: the
/// "no response values into script inputs" invariant is relaxed for
/// `follow_up` only, so a follow-up decision can react to what was actually
/// answered. `question_selection` keeps its ids+timestamps-only input. See
/// scripting.md §4.3.
library;

import '../errors.dart';
import '../schema.dart';
import 'round_types.dart';
import 'scheduling.dart' show resolvedSettingsSpec;

/// Contract revision (§4.5). Bump only on a breaking change.
///
/// 2 (0.6.0): grouped input — `settings` / `signals` / invocation values.
/// 3 (0.13.0): every timestamp is local epoch seconds in the zone of the run;
/// a `study` group with `zone`; the output accepts `trigger_in_seconds`.
/// 0.14.0 added `participant` to the round type (additive, still 3).
const int followUpContractVersion = 3;

/// The global Lua function the runtime invokes: `follow_up(input) -> output`.
const String followUpEntrypoint = 'follow_up';

/// The shape of one answered round, shared by `signals.current_round` and
/// each item of `signals.recent_rounds`. A round groups the answers a
/// participant gave at one trigger together with the prompt time
/// (`scheduled_at`), the response time (`answered_at`), and the response
/// latency (`delta_seconds`). Each answer carries its `values` — this is the
/// kind whose input includes answer values. `scheduled_at` and the two
/// `answered_at` are local epoch seconds in the zone of the run;
/// `delta_seconds` is a duration on the time line. The `type` is one of
/// [roundTypes] (`beep`, `follow_up`, `participant`), set by the host: a
/// follow-up round and a participant round (a self check-in) can themselves
/// be followed up.
TypeSpec _roundObject() => TypeSpec.object([
  Field('scheduled_at', TypeSpec.timestamp()),
  Field('answered_at', TypeSpec.timestamp()),
  Field('delta_seconds', TypeSpec.integer()),
  Field('type', TypeSpec.enumeration(roundTypes)),
  Field('tag', TypeSpec.string(), required: false, nullable: true),
  Field(
    'answers',
    TypeSpec.list(
      TypeSpec.object([
        Field('question_id', TypeSpec.string()),
        Field('values', TypeSpec.list(TypeSpec.string())),
        Field('answered_at', TypeSpec.timestamp()),
      ]),
    ),
  ),
]);

/// The frozen `follow_up` contract descriptor.
///
/// Every timestamp of the input and of the output is local epoch seconds in
/// the zone of the run (`study.zone`; `time-model.md` R5): the round and
/// answer times, the schedule entries, `now` and `follow_up.trigger_at`.
final ContractDescriptor followUpContract = ContractDescriptor(
  kind: ScriptKind.followUp,
  entrypoint: followUpEntrypoint,
  ioContractVersion: followUpContractVersion,
  input: Schema([
    // Study variables: the IANA zone this run resolves local times in.
    Field(
      'study',
      TypeSpec.object([
        Field(
          'zone',
          TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true),
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
        // The round the participant just answered.
        Field('current_round', _roundObject()),
        // Rounds answered during the 24 h before `now` (a duration on the
        // time line), grouped per round and ordered by `scheduled_at`.
        Field('recent_rounds', TypeSpec.list(_roundObject())),
        // The whole session timeline, so the script can see what is scheduled
        // and which entries have already been answered. trigger_at and
        // answered_at are local epoch seconds in the zone of the run.
        Field(
          'schedule',
          TypeSpec.list(
            TypeSpec.object([
              Field('trigger_at', TypeSpec.timestamp()),
              Field('tag', TypeSpec.string(), required: false, nullable: true),
              Field('type', TypeSpec.enumeration(roundTypes)),
              Field('answered', TypeSpec.boolean()),
              Field(
                'answered_at',
                TypeSpec.timestamp(),
                required: false,
                nullable: true,
              ),
              Field(
                'delta_seconds',
                TypeSpec.integer(),
                required: false,
                nullable: true,
              ),
            ]),
          ),
        ),
      ]),
    ),
    // Invocation values from the host: the answered round's completion time
    // (in simulation this equals the trigger time), as local epoch seconds in
    // the zone of the run, and the seed.
    Field('now', TypeSpec.timestamp()),
    Field('seed', TypeSpec.integer()),
  ]),
  output: Schema([
    // Absent/null => no follow-up round; otherwise the trigger to schedule:
    // a clock time (`trigger_at`, local epoch seconds) or a duration from
    // `now` (`trigger_in_seconds`). Exactly one of the two
    // (checkFollowUpOutput in output_rules.dart).
    Field(
      'follow_up',
      TypeSpec.object([
        Field(
          'trigger_at',
          TypeSpec.timestamp(),
          required: false,
          nullable: true,
        ),
        Field(
          'trigger_in_seconds',
          TypeSpec.integer(),
          required: false,
          nullable: true,
          constraint: const Constraint(min: 1),
        ),
        Field('tag', TypeSpec.string()),
      ]),
      required: false,
      nullable: true,
    ),
  ]),
);
