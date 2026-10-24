/// The output rules that the schema cannot express (docs/design/time-model.md
/// §3.3). The runtime applies them after the schema validation of the output.
library;

import 'errors.dart';

/// The message of a `follow_up` output that has both or neither of the two
/// trigger fields.
const String followUpExactlyOneMessage =
    'exactly one of trigger_at and trigger_in_seconds';

/// Check the rules of [kind] on a validated [output]. Throws a [ScriptError]
/// of type [ScriptErrorType.outputInvalid] when a rule fails.
void checkOutputRules(ScriptKind kind, Map<String, Object?> output) {
  if (kind == ScriptKind.followUp) checkFollowUpOutput(output);
}

/// A non-null `follow_up` has exactly one of `trigger_at` (a clock time) and
/// `trigger_in_seconds` (a duration from `now`). An absent or null
/// `follow_up` means "no follow-up round" and passes.
void checkFollowUpOutput(Map<String, Object?> output) {
  final followUp = output['follow_up'];
  if (followUp is! Map) return;
  final hasAt = followUp['trigger_at'] != null;
  final hasIn = followUp['trigger_in_seconds'] != null;
  if (hasAt == hasIn) {
    throw ScriptError(
      type: ScriptErrorType.outputInvalid,
      part: ScriptKind.followUp,
      message: followUpExactlyOneMessage,
      path: 'follow_up',
    );
  }
}
