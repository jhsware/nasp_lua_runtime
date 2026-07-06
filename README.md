# nasp_lua_runtime

The shared, pure-Dart Lua 5.3 runtime for nasp_waves scripting — the one
component that must be **byte-identical** in every host that executes scripts
(the server for simulation, the mobile app for live execution). See
`nasp_waves_server/docs/design/scripting.md` (authoritative spec) and
`docs/architecture/scripting-module.md` §5.

## What it provides

- `LuaScriptRuntime` — the sandboxed, deterministic execution engine over
  `lua_dardo_plus` (Lua 5.3, pure Dart; no FFI, no native build).
  `run(kind, source, input, {now, seed, budget})` validates the typed input,
  executes one script part, validates the output, and maps every failure onto
  the `ScriptError` taxonomy. `compile(kind, source)` is the static check.
- Per-kind **I/O contracts** (`scheduling`, `question_selection`) with
  `io_contract_version = 1`, serialisable as the contract descriptor served by
  `GET /script-bundles/contracts?kind=`.
- The explicit **schema type + validator** (path-qualified errors) and total,
  lossless **Dart↔Lua marshalling** (timestamps ↔ epoch seconds, int/double
  preserved).

## Sandbox guarantees

Scripts see only base + `math`/`string`/`table` plus host-injected `now()`,
seeded `random()`, and `log()` (captured to the trace). No `io`, `os`,
`require`, `package`, `dofile`, `loadfile`, `load`, `debug`, or `print`.
Budgets (host-call count, wall-clock, trace cap, output size) are enforced per
invocation. Note: a hard instruction-count budget for pure CPU loops is
deferred — the engine exposes only a line/breakpoint hook.

## Consuming

Depend on this package via a `git:` dependency **pinned to a tag/commit** so
both executing hosts resolve identical code:

```yaml
dependencies:
  nasp_lua_runtime:
    git:
      url: <this repository>
      ref: v0.1.0
```

The conformance test suite (`dart test`) is the acceptance gate for any future
engine swap: same fixtures, same inputs, identical outputs.
