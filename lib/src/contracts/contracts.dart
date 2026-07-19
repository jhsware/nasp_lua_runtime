/// The contract registry: every kind's I/O [ContractDescriptor], keyed by kind.
///
/// This is the single source of truth the runtime, the simulation engine, and
/// the `GET /script-bundles/contracts?kind=` endpoint all read (§4.1).
library;

import '../errors.dart';
import '../schema.dart';
import 'follow_up.dart';
import 'question_selection.dart';
import 'scheduling.dart';

export 'follow_up.dart';
export 'question_selection.dart';
export 'scheduling.dart';

/// All contract descriptors, keyed by [ScriptKind].
final Map<ScriptKind, ContractDescriptor> scriptContracts =
    Map.unmodifiable(<ScriptKind, ContractDescriptor>{
  ScriptKind.scheduling: schedulingContract,
  ScriptKind.questionSelection: questionSelectionContract,
  ScriptKind.followUp: followUpContract,
});

/// The contract descriptor for [kind], or null if the host has none.
ContractDescriptor? contractFor(ScriptKind kind) => scriptContracts[kind];
