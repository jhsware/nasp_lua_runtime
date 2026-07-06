/// The `scheduling` kind contract (docs/design/scripting.md §4.3).
///
/// Decide *when* to prompt a participant. Input is the participant's timezone,
/// the study window, the resolved schedule settings/rule (the same object the
/// `nasp_scheduling` domain versions — its `rule` is opaque JSON), the
/// enrolment date, the current wall-clock `now`, and the horizon to plan.
/// Output is an ordered list of tagged trigger times plus an optional
/// `regenerate_after` hint.
library;

import '../errors.dart';
import '../schema.dart';

/// Contract revision (§4.5). Bump only on a breaking change.
const int schedulingContractVersion = 1;

/// The global Lua function the runtime invokes: `schedule(input) -> output`.
const String schedulingEntrypoint = 'schedule';

/// The frozen `scheduling` contract descriptor.
final ContractDescriptor schedulingContract = ContractDescriptor(
  kind: ScriptKind.scheduling,
  entrypoint: schedulingEntrypoint,
  ioContractVersion: schedulingContractVersion,
  input: Schema([
    Field('timezone', TypeSpec.string(), constraint: const Constraint(nonEmpty: true)),
    Field('study_window', TypeSpec.object([
      Field('start', TypeSpec.timestamp()),
      Field('end', TypeSpec.timestamp()),
    ])),
    Field('settings', TypeSpec.object([
      Field('id', TypeSpec.string()),
      Field('scope', TypeSpec.string()),
      Field('study_id', TypeSpec.string(), required: false, nullable: true),
      Field('participant_id', TypeSpec.string(), required: false, nullable: true),
      Field('version', TypeSpec.integer()),
      Field('state', TypeSpec.string()),
      // The resolved rule is free-form JSON owned by nasp_scheduling.
      Field('rule', TypeSpec.json()),
    ])),
    Field('enrolment_date', TypeSpec.timestamp()),
    Field('now', TypeSpec.timestamp()),
    Field('horizon_days', TypeSpec.integer(), constraint: const Constraint(min: 1)),
  ]),
  output: Schema([
    Field(
      'triggers',
      TypeSpec.list(TypeSpec.object([
        Field('trigger_at', TypeSpec.timestamp()),
        Field('tag', TypeSpec.string(), required: false, nullable: true),
      ])),
    ),
    Field('regenerate_after', TypeSpec.timestamp(),
        required: false, nullable: true),
  ]),
);
