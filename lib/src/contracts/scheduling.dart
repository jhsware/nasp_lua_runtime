/// The `scheduling` kind contract (docs/design/scripting.md §4.3).
///
/// Decide *when* to prompt a participant. The input is grouped by provenance
/// (contract v2), so the structure itself tells a script author where each
/// value comes from:
///
///  - `study` — study variables, the same for every participant of the study:
///    the `zone` of the run, the study `window` (`start`/`end`), the
///    `horizon_days` to plan ahead, and the optional participant-relative
///    `length_days`.
///  - `settings` — the resolved script settings: the same object the
///    `nasp_scheduling` domain versions (its `rule` is opaque JSON). A
///    participant-scope override wins over the study-scope settings.
///  - `signals` — participant-specific data the script analyses. Today the
///    participant's identity (`participant_id`) and `enrolment_date`; later
///    device telemetry such as location and usage (additive). Anything
///    participant-specific is a signal.
///  - top-level — invocation values from the host: the wall-clock `now` and
///    an optional `seed` for host-provided randomness.
///
/// Every timestamp is local epoch seconds in the zone of the run (contract
/// v3, docs/design/time-model.md): the script sees wall-clock time and never
/// a DST change. Use the helpers `at_clock`, `add_days`, `local_time` and
/// `add_seconds`.
///
/// When `study.length_days` is given, the participant's effective study end is
/// `signals.enrolment_date + study.length_days`, clamped to `study.window.end`;
/// when it is omitted, `study.window.end` remains the effective end. Hosts
/// must not schedule triggers past the effective end.
/// Output is an ordered list of tagged trigger times plus an optional
/// `regenerate_after` hint.
library;

import '../errors.dart';
import '../schema.dart';

/// Contract revision (§4.5). Bump only on a breaking change.
///
/// 2 (0.6.0): grouped input — `study` / `settings` / `signals` / invocation
/// values; `signals.participant_id` added.
/// 2 (0.9.0): optional top-level `seed` added — additive, no bump.
/// 3 (0.13.0): every timestamp is local epoch seconds in the zone of the run;
/// `study.timezone` renamed `zone`.
const int schedulingContractVersion = 3;

/// The global Lua function the runtime invokes: `schedule(input) -> output`.
const String schedulingEntrypoint = 'schedule';

/// The resolved schedule settings object every kind can receive: the same
/// object the `nasp_scheduling` domain versions; its `rule` is opaque JSON
/// carrying the script-specific settings (BASSET). Required on the
/// `scheduling` input; optional (additive, non-breaking) on
/// `question_selection` and `follow_up`, where the server hosts supply it so
/// selection and follow-up decisions can read `settings.rule` too.
TypeSpec resolvedSettingsSpec() => TypeSpec.object([
  Field('id', TypeSpec.string()),
  Field('scope', TypeSpec.string()),
  Field('study_id', TypeSpec.string(), required: false, nullable: true),
  Field('participant_id', TypeSpec.string(), required: false, nullable: true),
  Field('version', TypeSpec.integer()),
  Field('state', TypeSpec.string()),
  // The resolved rule is free-form JSON owned by nasp_scheduling.
  Field('rule', TypeSpec.json()),
]);

/// The frozen `scheduling` contract descriptor.
/// The frozen `scheduling` contract descriptor.
///
/// Every timestamp of the input and of the output is local epoch seconds in
/// the zone of the run (`study.zone`; `time-model.md` R5): `window.start`,
/// `window.end`, `signals.enrolment_date`, `now`, `triggers[].trigger_at`
/// and `regenerate_after`.
final ContractDescriptor schedulingContract = ContractDescriptor(
  kind: ScriptKind.scheduling,
  entrypoint: schedulingEntrypoint,
  ioContractVersion: schedulingContractVersion,
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
        // The study window; start and end are local epoch seconds in the
        // zone of the run.
        Field(
          'window',
          TypeSpec.object([
            Field('start', TypeSpec.timestamp()),
            Field('end', TypeSpec.timestamp()),
          ]),
        ),
        Field(
          'horizon_days',
          TypeSpec.integer(),
          constraint: const Constraint(min: 1),
        ),
        // Optional participant-relative study length. Effective study end =
        // signals.enrolment_date + study.length_days, clamped to
        // study.window.end; when omitted the effective end is study.window.end.
        Field(
          'length_days',
          TypeSpec.integer(),
          required: false,
          nullable: true,
          constraint: const Constraint(min: 1),
        ),
      ]),
    ),
    // The resolved script settings (participant-scope override wins over
    // study scope).
    Field('settings', resolvedSettingsSpec()),
    // Participant-specific data the script analyses.
    Field(
      'signals',
      TypeSpec.object([
        Field(
          'participant_id',
          TypeSpec.string(),
          constraint: const Constraint(nonEmpty: true),
        ),
        // Local epoch seconds in the zone of the run.
        Field('enrolment_date', TypeSpec.timestamp()),
      ]),
    ),
    // Invocation values from the host: the current wall-clock time, as local
    // epoch seconds in the zone of the run.
    Field('now', TypeSpec.timestamp()),
    // Optional host seed for random(); the host also seeds the sandbox with it.
    Field('seed', TypeSpec.integer(), required: false, nullable: true),
  ]),
  output: Schema([
    // Each trigger_at is local epoch seconds in the zone of the run; the host
    // converts it to an instant with LocalTimeCodec.toInstant.
    Field(
      'triggers',
      TypeSpec.list(
        TypeSpec.object([
          Field('trigger_at', TypeSpec.timestamp()),
          Field('tag', TypeSpec.string(), required: false, nullable: true),
        ]),
      ),
    ),
    // Local epoch seconds in the zone of the run.
    Field(
      'regenerate_after',
      TypeSpec.timestamp(),
      required: false,
      nullable: true,
    ),
  ]),
);
