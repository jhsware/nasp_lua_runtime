# nasp_lua_runtime

The shared, pure-Dart Lua 5.3 runtime for nasp_waves scripting — the one
component that must be **byte-identical** in every host that executes scripts
(the server for simulation, the mobile app for live execution). See
`nasp_waves_server/docs/design/scripting.md` (authoritative spec) and
`docs/architecture/scripting-module.md` §5.

Design documents of this package are in `docs/design/`:
[time-model.md](docs/design/time-model.md) — local time in the scripts
(contract v3, 0.13.0): the `LocalTimeCodec`, the four host helpers and the
DST rules. The authority is `nasp_waves_server/docs/design/time-model.md`.

## What it provides

- `LuaScriptRuntime` — the sandboxed, deterministic execution engine over
  `lua_dardo_plus` (Lua 5.3, pure Dart; no FFI, no native build).
  `run(kind, source, input, {now, seed, budget})` validates the typed input,
  executes one script part, validates the output, and maps every failure onto
  the `ScriptError` taxonomy. `compile(kind, source)` is the static check.
- Per-kind **I/O contracts**: the bundle kinds (`scheduling`,
  `question_selection`, `follow_up`, listed in `ScriptKind.bundleParts`) with
  `io_contract_version = 3`, and the two kinds of a branched question, never
  a bundle part: `question_follow_up` (the branching script) and
  `question_dynamic` (the dynamic questions script), each with
  `io_contract_version = 2`.
  Each is serialisable as the contract descriptor served by
  `GET /script-bundles/contracts?kind=`. Every timestamp of every contract is
  local epoch seconds in the zone of the run (see
  [Local-time helpers](#local-time-helpers)).
- `LocalTimeCodec` — the conversion between an instant and the local
  wall-clock time in an IANA zone: `toLocal`, `toInstant` (a gap moves
  forward to the transition, an overlap takes the earlier instant) and
  `isValidZone`. Both hosts call it before and after each run.
- The four **local-time helpers** of the sandbox: `local_time`, `at_clock`,
  `add_days`, `add_seconds`.
- The explicit **schema type + validator** (path-qualified errors) and total,
  lossless **Dart↔Lua marshalling** (timestamps ↔ epoch seconds, int/double
  preserved). A `timestamp` value is an integer, a double, or an ISO-8601
  string with `Z`; a string with an offset or without a zone is refused
  (0.13.1). `Field` carries three advisory slots for bundle-declared
  settings schemas, all ignored by the validator: `description` (prose),
  `from_question` (the enrolment question whose answer seeds the field, read
  by the server's settings derivation), and `format` (a display hint for a
  `string` field — `time` for `HH:mm`, `date` for `yyyy-MM-dd` — read by
  client forms). `Field` also carries `participant_editable` (see
  [Participant-editable settings](#participant-editable-settings)).

## The tz database

`LocalTimeCodec` uses `package:timezone` (`^0.11.0`, pure Dart) with the full
database `data/latest_all.dart`: every canonical zone and every link name
(for example `Europe/Kiev` and `US/Eastern`, which a phone can report), with
the full history. The embedded tz data is about 430 KB (`latest_all.tzf`
441,320 bytes in timezone 0.11.2; `latest_10y.tzf` is 66,768 bytes but has
only the canonical zones for a window of years around the data release). The
codec loads it on its first call into the global database of
`package:timezone`; a host must not later load a smaller variant. The tz data
rides on the tag of this package, so two hosts that pin the same tag convert
identically. A new tz release comes with a new runtime tag.

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

## Contract v3: grouped inputs in local time

Every script input is grouped by provenance, so the structure itself tells a
script author where a value comes from:

| group | contents | example paths |
| --- | --- | --- |
| `input.study` | Study variables — the same for every participant of the study. `study.zone` is the IANA zone of the run. | `study.zone`, `study.window.start`, `study.horizon_days`, `study.length_days`, `study.question_sets`, `study.questions` |
| `input.question` | `question_follow_up` and `question_dynamic` only. The branched question and its members — the same for every participant. | `question.id`, `question.root_question_id`, `question.questions` |
| `input.step` | `question_dynamic` only. The step of the presentation that the host runs now. | `step.index`, `step.question_ids` |
| `input.settings` | The resolved script settings. A participant-scope override wins over the study scope; `settings.rule` carries the script-specific keys. | `settings.rule` |
| `input.signals` | Participant-specific data the script analyses. **Anything participant-specific is a signal.** Device telemetry (location, usage) will be added here later, additively. | `signals.participant_id`, `signals.enrolment_date`, `signals.answers`, `signals.current_round`, `signals.recent_rounds`, `signals.schedule` |
| top-level | Invocation values from the host. | `now`, `seed`, `trigger`, `zone` (branch kinds) |

Every timestamp, in the input and in the output, is **local epoch seconds**
in the zone of the run (see [Local-time helpers](#local-time-helpers)).
Durations (`delta_seconds`, `trigger_in_seconds`, the 24 h of
`recent_rounds`) are on the time line.

Per kind:

- `scheduling` — `schedule(input)` (contract 3): `study {zone, window,
  horizon_days, length_days?}`, `settings`, `signals {participant_id,
  enrolment_date}`, `now`, `seed?`. The seed is optional here (0.9.0); it is
  required on the other kinds. A host that sends none leaves `random()`
  seeded with 0. Output `triggers[] {trigger_at, tag?}`, `regenerate_after?`.
- `question_selection` — `select_questions(input)` (contract 3): `study
  {zone, question_sets, questions}`, `settings?`, `signals {participant_id,
  answers}`, `trigger`, `seed`. Each catalog question has an optional
  `mandatory` (0.15.0): its effective setting. Output `items[] {id, kind,
  mandatory?}` and `reason?`; `mandatory = true` makes the item mandatory in
  this round (a question, every member of a set, or the root of a branched
  question).
- `follow_up` — `follow_up(input)` (contract 3): `study {zone}`, `settings?`,
  `signals {participant_id, current_round, recent_rounds, schedule}`, `now`,
  `seed`. Output `follow_up?`: `{trigger_at, tag}` (a clock time) or
  `{trigger_in_seconds, tag}` (a duration from `now`, an int >= 1). A
  non-null `follow_up` with both or with neither is `outputInvalid` at
  `follow_up`: `exactly one of trigger_at and trigger_in_seconds`.
- `question_follow_up` — `follow_up_questions(input)` (0.10.0; contract 2
  since 0.13.0): `question {id, root_question_id, questions}`, `signals
  {participant_id, answers}`, `now`, `zone`, `seed`. The script of a
  branched question. It is not a bundle part (see `ScriptKind.bundleParts`).
  The `question` group holds the branched question and its members; it is
  the same for each participant. Each member has an optional `mandatory`
  (0.15.0): its effective setting. Each answer carries its `values`; a
  skipped question, the root too when it is optional, has an empty list.
  The output is `questions` (a list of `{id, mandatory?}`;
  `mandatory = true` makes that follow-up question mandatory in this
  presentation) and `reason`, both optional. A script can declare
  `requires_root_answer` (see [Script declarations](#script-declarations)).
- `question_dynamic` — `dynamic_questions(input)` (0.11.0; contract 2 since
  0.13.0): `question {id, root_question_id, questions}` (each member also
  has `dynamic`, the base `text`, the base `options` `{label, value,
  position}` and an optional `mandatory` (0.15.0)), `step {index,
  question_ids}`, `signals {participant_id, answers,
  earlier_presentations}` (each earlier presentation has
  `schedule_entry_id`, `answered_at` and `answers`), `now`, `zone`, `seed`.
  The dynamic questions script of a branched question. It is not a bundle
  part. The output is `questions` (a list of `{id, text?, options?, key?}`;
  an option is `{label, value}` with no position) and `reason`, both
  optional. The output has no `type` or `type_config` field: the validator
  drops an undeclared key.

Each `mandatory` is an optional, nullable boolean; the runtime enforces
nothing. A nullable output field that the script leaves nil comes back as
`null`, so an item without `mandatory` has `mandatory: null`.

A v1-shaped (flat) bundle input, or a v2 input without `zone`, is rejected
with a path-qualified `inputInvalid` error. The prose documentation of every
field lives in the server's input reference, not in this package.

## Sandbox guarantees

Scripts see only base + `math`/`string`/`table` plus host-injected `now()`,
seeded `random()`, `log()` (captured to the trace) and the four local-time
helpers (below). No `io`, `os`, `require`, `package`, `dofile`, `loadfile`,
`load`, `debug`, or `print`. Budgets (host-call count, wall-clock, trace cap,
output size) are enforced per invocation. Note: a hard instruction-count
budget for pure CPU loops is deferred — the engine exposes only a
line/breakpoint hook.

## Local-time helpers

Since 0.13.0 every timestamp a script sees is **local epoch seconds** in the
zone of the run: the epoch seconds of the wall-clock time read as if it were
UTC (`2026-10-25 07:00` is `1792911600` in any zone). Four pure helpers work
on these integers (`lib/src/host_helpers.dart`); the tz database is not
involved:

| helper | returns |
| --- | --- |
| `local_time(ts)` | the table `{year, month, day, hour, minute, second, weekday, yday}`; `weekday` is 1 = Monday to 7 = Sunday, `yday` is 1 to 366 |
| `at_clock(ts, "HH:mm")` | the local epoch second of that clock time on the day of `ts` |
| `add_days(ts, n)` | `ts + n * 86400`: the same clock time `n` days later; `n` may be negative |
| `add_seconds(ts, n)` | `ts + n` |

Each helper counts as a host call. They exist in `run` and in `compile`.
An argument that is not an integer raises `<helper>: argument <i> (<name>)
must be an integer` (a float with no fraction, such as the result of `/`,
counts as an integer); a value outside the range of a date raises
`<helper>: argument <i> (<name>) is out of range`; a clock string that is not
two digits, a colon and two digits (00–23, 00–59) raises `at_clock: expected
"HH:mm"`. As with the string guards, the engine adds no line number; the
helper name locates the call. The tests are in `test/host_helpers_test.dart`.

## String functions

The engine does not support the Lua patterns. Since 0.12.0 a string function
that would use a pattern raises a clear error instead of a silent wrong
result. A text is a *pattern* when it contains one of the special characters
`^ $ * + ? . ( ) [ ] % -`.

| call | rule |
| --- | --- |
| `s:find(p, init, plain)` | allowed when `plain` is true, or when `p` is not a pattern |
| `s:match(p, init)` | allowed when `p` is not a pattern |
| `s:gsub(p, repl, n)` | allowed when `p` is not a pattern and `repl` is a string (or a number) without `%` |
| `s:gmatch(p)` | always an error |
| `s:reverse()` | always an error |
| `sub`, `len`, `upper`, `lower`, `rep`, `byte`, `char`, `string.format` | unchanged |

A forbidden call raises `string.<name>: Lua patterns are not supported; use
<hint>`, with the hint `s:find(text, init, true)`, `a loop with s:find(text,
init, true) and s:sub(i, j)`, `a replacement without %` or `a loop with
s:sub(i, i)`. The engine adds no line number to this error; the function name
locates the call. `#s` on a string is an engine error; the runtime appends
`use s:len() for the length of a string` to the message. The guards apply
through `string.find(...)` and through `s:find(...)`, in `compile` and in
`run`. The tests are in `test/string_guards_test.dart`; the rule for script
authors is in `nasp_waves_server/docs/design/scripting.md` §6.2.

## Script declarations

Since 0.15.0 a branching script (`question_follow_up`) that needs a value
for the root question declares it with one global boolean at the top level
of the chunk:

```lua
requires_root_answer = true

function follow_up_questions(input)
  -- input.signals.answers[1] is the root answer; with an optional root
  -- its values list can be empty (a skip).
  return {}
end
```

The host reads it with the synchronous
`LuaScriptRuntime.declarations(kind, source)`, which returns a
`ScriptDeclarationsResult` with `error` and `declarations`
(`ScriptDeclarations.requiresRootAnswer`; `toJson()` gives
`{'requires_root_answer': bool}`). It runs the checks of `compile` first
and returns their error. An absent or nil global is `false`; a value that
is not a boolean is a `compile` error `requires_root_answer must be a
boolean`. For every other kind the global is not read and the result is
`false`. The runtime does not enforce the declaration and `run` never
reads it: the server compares it with the effective setting of the root
and warns (`nasp_waves_server/docs/design/mandatory-questions.md` §8).

## Consuming

Depend on this package via a `git:` dependency **pinned to a tag/commit** so
both executing hosts resolve identical code:

```yaml
dependencies:
  nasp_lua_runtime:
    git:
      url: <this repository>
      ref: v0.15.0
```

A host that moves to 0.13.0 or later must convert every timestamp with
`LocalTimeCodec` and fill the `zone` of the run (see the `## 0.13.0` entry
of `CHANGELOG.md`). A timestamp string must end with `Z` (0.13.1). The
server and the phone pin the same tag, so they use the same tz data.

The conformance test suite (`dart test`) is the acceptance gate for any future
engine swap: same fixtures, same inputs, identical outputs.
