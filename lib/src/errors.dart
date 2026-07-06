/// Cross-host error taxonomy and script-kind identifiers.
///
/// See docs/design/scripting.md §3.1 (kinds) and §6.4 (the `ScriptError`
/// taxonomy). A single error type crosses both hosts and always identifies the
/// part (kind) it arose in, so a bundle-level operation (e.g. an end-to-end
/// simulation) can attribute failures precisely.
library;

/// The kinds of script a bundle contains. Each kind selects an input schema,
/// an output schema, an entry-point signature, and a simulation harness
/// (scripting.md §3.1). Closed enum in code, designed for extension.
enum ScriptKind {
  /// Decide the trigger times for a participant over a horizon.
  scheduling('scheduling'),

  /// Decide which question(s)/set to present at a given trigger.
  questionSelection('question_selection');

  const ScriptKind(this.id);

  /// Stable id string — the manifest key, the git file stem, and the wire
  /// value used by the REST API (`?kind=`).
  final String id;

  /// Resolve a [ScriptKind] from its [id], or null if unknown.
  static ScriptKind? fromId(String id) {
    for (final k in ScriptKind.values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// The single error taxonomy that crosses both hosts (scripting.md §6.4).
enum ScriptErrorType {
  /// The source did not load/parse.
  compile,

  /// The input failed contract validation (path-qualified).
  inputInvalid,

  /// A Lua error was raised during the call.
  runtime,

  /// The output failed contract validation (path-qualified).
  outputInvalid,

  /// An execution budget (steps, wall-clock, or memory) was exceeded.
  budgetExceeded,

  /// The script targets a contract/runtime version the host does not implement.
  contractUnsupported,
}

/// A part-attributed, optionally path-qualified script error.
///
/// Implements [Exception] so host code that prefers throwing can, but
/// [LuaScriptRuntime.run] returns it as a value on the result rather than
/// throwing (scripting.md §6.4: it is "returned directly to the host").
class ScriptError implements Exception {
  ScriptError({
    required this.type,
    required this.part,
    required this.message,
    this.path,
  });

  /// Where in the taxonomy this failure sits.
  final ScriptErrorType type;

  /// The part (kind) the error arose in.
  final ScriptKind part;

  /// A human-readable description.
  final String message;

  /// For [ScriptErrorType.inputInvalid] / [ScriptErrorType.outputInvalid]:
  /// the field path, e.g. `triggers[3].trigger_at`. Null otherwise.
  final String? path;

  @override
  String toString() {
    final loc = (path == null || path!.isEmpty) ? '' : ' at $path';
    return '${part.id}/${type.name}$loc: $message';
  }

  /// Serialise for the REST error envelope / SSE payloads.
  Map<String, Object?> toJson() => {
        'type': type.name,
        'part': part.id,
        'message': message,
        if (path != null && path!.isNotEmpty) 'path': path,
      };
}
