/// The sandboxed, deterministic Lua execution engine (docs/design/scripting.md
/// §6).
///
/// [LuaScriptRuntime.run] validates a kind-typed input, executes exactly one
/// part in an explicitly-constructed sandbox, validates the output, and maps
/// every failure onto the [ScriptError] taxonomy. Given the same source,
/// input, `now`, and `seed`, the output is deterministic — the property that
/// makes server simulation a faithful prediction of device execution.
library;

import 'dart:convert';
import 'dart:math';

import 'package:lua_dardo_plus/lua.dart';

import 'contracts/contracts.dart';
import 'errors.dart';
import 'marshal.dart';

/// Per-invocation execution budget (§6.3). Budgets apply per part invocation.
///
/// Note on the instruction/step budget: the underlying pure-Dart engine does
/// not expose a periodic instruction-count hook, so a *pure* CPU loop that
/// calls no host function cannot be pre-empted synchronously. The enforced
/// controls are the host-call budget ([maxHostCalls]), the cooperative
/// wall-clock check ([timeout], evaluated on every host call), the trace cap
/// ([maxTraceEntries]), and the output-size ceiling ([maxOutputBytes]). A
/// hard, hook-based step budget is deferred to a runtime that exposes one (the
/// seam is deliberately narrow so it can be added or the engine swapped —
/// analysis §3).
class RuntimeBudget {
  const RuntimeBudget({
    this.maxHostCalls = 100000,
    this.timeout = const Duration(seconds: 2),
    this.maxTraceEntries = 1000,
    this.maxOutputBytes = 1 << 20,
  });

  /// Maximum number of host-function calls (`now`/`random`/`log`).
  final int maxHostCalls;

  /// Wall-clock ceiling, checked cooperatively on every host call.
  final Duration timeout;

  /// Maximum number of `log()` lines retained in the trace.
  final int maxTraceEntries;

  /// Memory ceiling proxy: the serialised output may not exceed this size.
  final int maxOutputBytes;
}

/// The outcome of one part invocation: either a validated [output] or an
/// [error], always with the captured [trace] and cost metrics.
class ScriptRunResult {
  ScriptRunResult({
    this.output,
    this.error,
    required this.trace,
    required this.hostCalls,
    required this.elapsed,
  });

  /// The validated, typed output (timestamps as [DateTime]); null on error.
  final Map<String, Object?>? output;

  /// The failure, or null on success.
  final ScriptError? error;

  /// Lines captured from `log()`.
  final List<String> trace;

  /// Number of host-function calls made.
  final int hostCalls;

  /// Wall-clock time spent.
  final Duration elapsed;

  bool get ok => error == null;
}

/// Internal sentinel used to unwind out of the interpreter when a budget is
/// exceeded from within a host function.
class _BudgetExceeded implements Exception {
  const _BudgetExceeded(this.reason);
  final String reason;
}

/// The narrow, stable seam both hosts depend on (§6.1). Stateless: each [run]
/// builds a fresh Lua state, so runs never share mutable interpreter state.
class LuaScriptRuntime {
  const LuaScriptRuntime();

  /// The runtime package version, matched against `runtime_min_version` (§3.3).
  ///
  /// Must equal the `version:` field of `pubspec.yaml` — a host compares a
  /// bundle's `runtime_min_version` against this constant to decide whether it
  /// can execute the bundle. `test/version_test.dart` guards the two against
  /// drift.
  static const String version = '0.7.0';

  /// Execute one [kind] part.
  ///
  /// [input] is a raw JSON-like map (validated against the input contract
  /// before Lua runs). [now] is the host-supplied wall clock exposed to the
  /// script as `now()` (defaults to epoch 0 for determinism if omitted).
  /// [seed] seeds the sandbox `random()`.
  ScriptRunResult run(
    ScriptKind kind,
    String source,
    Map<String, Object?> input, {
    DateTime? now,
    int seed = 0,
    RuntimeBudget budget = const RuntimeBudget(),
  }) {
    final trace = <String>[];
    final sw = Stopwatch()..start();
    var hostCalls = 0;

    ScriptRunResult err(ScriptError e) => ScriptRunResult(
          error: e,
          trace: trace,
          hostCalls: hostCalls,
          elapsed: sw.elapsed,
        );
    ScriptRunResult typed(ScriptErrorType t, String message, {String? path}) =>
        err(ScriptError(type: t, part: kind, message: message, path: path));

    final contract = contractFor(kind);
    if (contract == null) {
      return typed(ScriptErrorType.contractUnsupported,
          'no contract registered for kind ${kind.id}');
    }

    // 1. Validate input — a bad input never enters Lua (§4.4).
    final Map<String, Object?> typedInput;
    try {
      typedInput = contract.input.validate(input, part: kind, input: true);
    } on ScriptError catch (e) {
      return err(e);
    }

    // 2. Construct the sandbox explicitly (§6.2).
    final effectiveNow =
        (now ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)).toUtc();
    final rng = Random(seed);
    final nowEpoch = effectiveNow.millisecondsSinceEpoch ~/ 1000;

    String? budgetReason;
    void checkBudget() {
      if (budgetReason != null) return;
      if (sw.elapsed > budget.timeout) {
        budgetReason = 'wall-clock timeout exceeded';
        throw const _BudgetExceeded('timeout');
      }
      if (hostCalls > budget.maxHostCalls) {
        budgetReason = 'host-call budget exceeded';
        throw const _BudgetExceeded('host-calls');
      }
    }

    final ls = LuaState.newState();
    ls.openLibs();
    _sealSandbox(ls);

    // now() -> host clock (epoch seconds), never the real clock.
    ls.pushDartFunction((s) {
      hostCalls++;
      checkBudget();
      s.pushInteger(nowEpoch);
      return 1;
    });
    ls.setGlobal('now');

    // random([m[, n]]) -> seeded PRNG: [0,1), [1,m], or [m,n].
    ls.pushDartFunction((s) {
      hostCalls++;
      checkBudget();
      final argc = s.getTop();
      if (argc <= 0) {
        s.pushNumber(rng.nextDouble());
        return 1;
      }
      if (argc == 1) {
        final m = s.toInteger(1);
        final upper = m < 1 ? 1 : m;
        s.pushInteger(1 + rng.nextInt(upper));
        return 1;
      }
      final lo = s.toInteger(1);
      final hi = s.toInteger(2);
      final span = hi - lo < 0 ? 0 : hi - lo;
      s.pushInteger(lo + rng.nextInt(span + 1));
      return 1;
    });
    ls.setGlobal('random');

    // log(msg) -> captured into the trace, not stdout.
    ls.pushDartFunction((s) {
      hostCalls++;
      checkBudget();
      final msg = s.toStr(1) ?? '';
      if (trace.length < budget.maxTraceEntries) trace.add(msg);
      return 0;
    });
    ls.setGlobal('log');

    // A protected-call helper. `loadString`/`pCall` may throw Dart exceptions,
    // and the protected `pCall` swallows the exception a host function throws to
    // signal a budget abort — so budgets are surfaced via [budgetReason], which
    // callers check before the returned message.
    String? protectedCall(int nargs, int nresults) {
      try {
        if (ls.pCall(nargs, nresults, 0) != ThreadStatus.luaOk) {
          return ls.toStr(-1) ?? 'runtime error';
        }
        return null;
      } on _BudgetExceeded {
        return null;
      } catch (e) {
        return _luaMessage(e);
      }
    }

    // 3. Compile. A syntax error may throw or return a non-OK status.
    try {
      if (ls.loadString(source) != ThreadStatus.luaOk) {
        return typed(ScriptErrorType.compile, ls.toStr(-1) ?? 'compile error');
      }
    } catch (e) {
      return typed(ScriptErrorType.compile, _luaMessage(e));
    }

    // 4. Run the top-level chunk (defines the entry point).
    final topError = protectedCall(0, 0);
    if (budgetReason != null) {
      return typed(ScriptErrorType.budgetExceeded, budgetReason!);
    }
    if (topError != null) return typed(ScriptErrorType.runtime, topError);

    // 5. Resolve and invoke the entry point with the marshalled input.
    ls.getGlobal(contract.entrypoint);
    if (!ls.isFunction(-1)) {
      return typed(ScriptErrorType.runtime,
          "entry point '${contract.entrypoint}' is not defined");
    }
    try {
      pushDartValue(ls, typedInput);
    } catch (e) {
      return typed(ScriptErrorType.runtime, 'failed to marshal input: $e');
    }
    final callError = protectedCall(1, 1);
    if (budgetReason != null) {
      return typed(ScriptErrorType.budgetExceeded, budgetReason!);
    }
    if (callError != null) return typed(ScriptErrorType.runtime, callError);

    // 6. Read + validate the output (§4.4).
    final Map<String, Object?> output;
    try {
      output = readLuaValue(ls, contract.output.asType, '', kind)
          as Map<String, Object?>;
    } on ScriptError catch (e) {
      return err(e);
    }

    // 7. Memory ceiling proxy: serialised output size.
    final bytes = utf8.encode(jsonEncode(scriptValueToJson(output)));
    if (bytes.length > budget.maxOutputBytes) {
      return typed(ScriptErrorType.budgetExceeded,
          'output exceeds ${budget.maxOutputBytes} bytes');
    }

    return ScriptRunResult(
      output: output,
      trace: trace,
      hostCalls: hostCalls,
      elapsed: sw.elapsed,
    );
  }

  /// Compile-check a [kind] part without executing it: loads the source in the
  /// sandbox and verifies the kind's entry point is defined. Returns null on
  /// success, or a [ScriptError] (compile / runtime / contractUnsupported).
  /// Backs the REST `/validate` surface and pre-simulation checks.
  ScriptError? compile(ScriptKind kind, String source) {
    final contract = contractFor(kind);
    if (contract == null) {
      return ScriptError(
        type: ScriptErrorType.contractUnsupported,
        part: kind,
        message: 'no contract registered for kind ${kind.id}',
      );
    }
    final ls = LuaState.newState();
    ls.openLibs();
    _sealSandbox(ls);
    for (final name in const ['now', 'random', 'log']) {
      ls.pushDartFunction((s) => 0);
      ls.setGlobal(name);
    }
    try {
      if (ls.loadString(source) != ThreadStatus.luaOk) {
        return ScriptError(
          type: ScriptErrorType.compile,
          part: kind,
          message: ls.toStr(-1) ?? 'compile error',
        );
      }
    } catch (e) {
      return ScriptError(
        type: ScriptErrorType.compile,
        part: kind,
        message: _luaMessage(e),
      );
    }
    try {
      if (ls.pCall(0, 0, 0) != ThreadStatus.luaOk) {
        return ScriptError(
          type: ScriptErrorType.runtime,
          part: kind,
          message: ls.toStr(-1) ?? 'runtime error',
        );
      }
    } catch (e) {
      return ScriptError(
        type: ScriptErrorType.runtime,
        part: kind,
        message: _luaMessage(e),
      );
    }
    ls.getGlobal(contract.entrypoint);
    if (!ls.isFunction(-1)) {
      return ScriptError(
        type: ScriptErrorType.runtime,
        part: kind,
        message: "entry point '${contract.entrypoint}' is not defined",
      );
    }
    return null;
  }

  /// Strip every ambient capability that is not part of the sanctioned set
  /// (§6.2): no `io`/`os`/`package`/`require`/`dofile`/`loadfile`/`load`/
  /// `debug`/`print`, and no nondeterministic `math.random`. What remains is
  /// base + `math` + `string` + `table` (plus injected `now`/`random`/`log`).
  void _sealSandbox(LuaState ls) {
    const dangerous = <String>[
      'io',
      'os',
      'package',
      'require',
      'dofile',
      'loadfile',
      'load',
      'loadstring',
      'collectgarbage',
      'debug',
      'print',
    ];
    for (final name in dangerous) {
      ls.pushNil();
      ls.setGlobal(name);
    }
    ls.getGlobal('math');
    if (ls.isTable(-1)) {
      ls.pushNil();
      ls.setField(-2, 'random');
      ls.pushNil();
      ls.setField(-2, 'randomseed');
    }
    ls.pop(1);
  }
}

/// Extract a concise message from a Lua/engine error object.
String _luaMessage(Object e) {
  final s = e.toString();
  const prefix = 'Exception: ';
  return s.startsWith(prefix) ? s.substring(prefix.length) : s;
}

/// Convert a typed script value (as returned on [ScriptRunResult.output]) into
/// a JSON-encodable value: [DateTime] becomes an ISO-8601 UTC string, maps and
/// lists are converted recursively. Host code uses this to serialise outputs
/// for the REST envelope / SSE payloads.
Object? scriptValueToJson(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map) {
    return value.map(
        (k, v) => MapEntry(k.toString(), scriptValueToJson(v)));
  }
  if (value is List) return value.map(scriptValueToJson).toList();
  return value;
}
