/// nasp_lua_runtime — the one runtime that runs script parts everywhere.
///
/// This package is the shared seam that guarantees the subsystem's core
/// promise: "one script, one behaviour, everywhere" (docs/design/scripting.md
/// §2). Both executing hosts — the server (simulation) and the mobile app
/// (live execution) — embed this exact code, so a simulation is a faithful
/// prediction of what a device will do.
///
/// Public surface:
///  - [LuaScriptRuntime] — the sandboxed, deterministic execution engine.
///  - [ScriptError] / [ScriptErrorType] / [ScriptKind] — the cross-host error
///    taxonomy (§6.4).
///  - The schema types ([Schema], [TypeSpec], [Field], [Constraint]) and the
///    per-kind [ContractDescriptor]s consumed by `GET /script-bundles/contracts`.
///    Contract v2 groups every input by provenance: `study` (study
///    variables), `settings` (the resolved script settings), `signals`
///    (participant-specific data — anything participant-specific is a
///    signal) and top-level invocation values (`now`, `seed`, `trigger`).
library;

export 'src/contracts/contracts.dart';
export 'src/errors.dart';
export 'src/schema.dart';
export 'src/vm.dart';
