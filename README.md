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
- Per-kind **I/O contracts** (`scheduling`, `question_selection`,
  `follow_up`) with `io_contract_version = 2`, serialisable as the contract
  descriptor served by `GET /script-bundles/contracts?kind=`.
- The explicit **schema type + validator** (path-qualified errors) and total,
  lossless **Dart↔Lua marshalling** (timestamps ↔ epoch seconds, int/double
  preserved). `Field.description` is an optional, advisory prose slot for
  bundle-declared settings schemas.

## Contract v2: grouped inputs

Every script input is grouped by provenance, so the structure itself tells a
script author where a value comes from:

| group | contents | example paths |
| --- | --- | --- |
| `input.study` | Study variables — the same for every participant of the study. | `study.timezone`, `study.window.start`, `study.horizon_days`, `study.length_days`, `study.question_sets`, `study.questions` |
| `input.settings` | The resolved script settings. A participant-scope override wins over the study scope; `settings.rule` carries the script-specific keys. | `settings.rule` |
| `input.signals` | Participant-specific data the script analyses. **Anything participant-specific is a signal.** Device telemetry (location, usage) will be added here later, additively. | `signals.participant_id`, `signals.enrolment_date`, `signals.answers`, `signals.current_round`, `signals.recent_rounds`, `signals.schedule` |
| top-level | Invocation values from the host. | `now`, `seed`, `trigger` |

Per kind:

- `scheduling` — `schedule(input)`: `study {timezone, window, horizon_days,
  length_days?}`, `settings`, `signals {participant_id, enrolment_date}`,
  `now`.
- `question_selection` — `select_questions(input)`: `study {question_sets,
  questions}`, `settings?`, `signals {participant_id, answers}`, `trigger`,
  `seed`.
- `follow_up` — `follow_up(input)`: `settings?`, `signals {participant_id,
  current_round, recent_rounds, schedule}`, `now`, `seed`. No `study` group
  yet (adding one later is additive).

Outputs are unchanged from v1. A v1-shaped (flat) input is rejected with a
path-qualified `inputInvalid` error at the first missing group. The prose
documentation of every field lives in the server's input reference, not in
this package.

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
      ref: v0.6.0
```

The conformance test suite (`dart test`) is the acceptance gate for any future
engine swap: same fixtures, same inputs, identical outputs.
