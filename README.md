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
  preserved). `Field` carries three advisory slots for bundle-declared
  settings schemas, all ignored by the validator: `description` (prose),
  `from_question` (the enrolment question whose answer seeds the field, read
  by the server's settings derivation), and `format` (a display hint for a
  `string` field — `time` for `HH:mm`, `date` for `yyyy-MM-dd` — read by
  client forms). `Field` also carries `participant_editable` (see
  [Participant-editable settings](#participant-editable-settings)).

## Participant-editable settings

An operator can mark a field of a bundle-declared settings schema as editable
by the participant. The participant edits the field in the mobile app
(Settings > Personalise). The server enforces the bounds on every settings
write. Both hosts use the same parser (`Schema.fromJson`) and the same
validator (`Schema.validate`).

Set `participant_editable: true` on the field. The key is a bool. Absent
means false. The key is serialised only when true, so a descriptor without it
is byte-identical to its 0.7.0 form.

The field must have one of six edit kinds (`SettingsEditKind`). The kind
follows from the shape of the field (`Field.editKind`):

| kind | wire shape | bounds |
| --- | --- | --- |
| `integer` | type `int` | numbers |
| `decimal` | type `double` | numbers |
| `time` | type `string`, `format: time` | `HH:mm` strings |
| `date` | type `string`, `format: date` | `yyyy-MM-dd` strings |
| `time_span` | type `object`, `format: time_span`, exactly the `string` fields `start` and `end`, each with `format: time` | `HH:mm` strings, applied to `start` and to `end` |
| `date_span` | type `object`, `format: date_span`, exactly the `string` fields `start` and `end`, each with `format: date` | `yyyy-MM-dd` strings, applied to `start` and to `end` |

Example (a time span from 22:00 to 06:00 is valid):

```json
{
  "name": "quiet_hours",
  "type": {
    "type": "object",
    "fields": [
      {"name": "start", "type": {"type": "string"}, "required": true, "nullable": false, "format": "time"},
      {"name": "end", "type": {"type": "string"}, "required": true, "nullable": false, "format": "time"}
    ]
  },
  "required": true,
  "nullable": false,
  "constraint": {"min": "06:00", "max": "23:30"},
  "format": "time_span",
  "participant_editable": true
}
```

Rules:

- `constraint.min` and `constraint.max` are a number or a non-empty string.
  In Dart they are `Object?`. Read them with `numMin`, `numMax`, `stringMin`
  and `stringMax`.
- A number bound is valid only on an `int` or `double` field.
- A string bound is valid only on a `time`, `date`, `time_span` or
  `date_span` field.
- `participant_editable: true` is valid only on a field with an edit kind. A
  `bool`, `enum`, `timestamp`, `list`, `map` or `json` field, or another
  object, cannot be participant-editable.
- `format: time_span` and `format: date_span` are valid only on the span
  object shape.
- `Field.fromJson` rejects each violation with a path-qualified
  `FormatException`.
- The validator compares string bounds lexicographically. Use the canonical
  `HH:mm` and `yyyy-MM-dd` forms. On a span, the validator checks `start` and
  `end` separately and reports the part path (for example
  `rule.quiet_hours.end: must be <= 23:30`). It does not require
  `start <= end`.

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
      ref: v0.8.0
```

The conformance test suite (`dart test`) is the acceptance gate for any future
engine swap: same fixtures, same inputs, identical outputs.
