# Changelog

## Unreleased

**Documentation.**

- Doc comments in `lib/src/contracts/scheduling.dart`: `signals.enrolment_date`
  is the moment the participant enrolled, a local time with a clock time, not
  midnight of a date. A script can schedule relative to it, for example
  `add_seconds(input.signals.enrolment_date, 300)`.

**Compatibility.** A documentation clarification only. No field, type,
validation or contract version changes (`scheduling` stays at 3). The hosts
need no new pin.
## 0.14.0

The round type of a self check-in: a round the participant starts on their
own from the mobile app (`type: participant`, tag `participant`). `follow_up`
now runs after such a round too, and both bundle kinds can tell it from a
regular beep.

**Added.**

- `participant` in the round type of `follow_up`: `signals.current_round.type`,
  `signals.recent_rounds[].type` and `signals.schedule[].type` accept `beep`,
  `follow_up` and `participant`. An unknown type is still `inputInvalid` at
  its field path.
- An optional `trigger.type` on `question_selection`, with the same
  enumeration. The host sets it; the tag stays the scheduling script's
  choice. An unknown value is `inputInvalid` at `trigger.type`.
- `roundTypes` and the constants `roundTypeBeep`, `roundTypeFollowUp`,
  `roundTypeParticipant` (`lib/src/contracts/round_types.dart`, exported):
  the one enumeration both contracts use.

**Compatibility.** No contract version changes (`follow_up` and
`question_selection` stay at 3). A host that sends neither value behaves as
in 0.13.1. A script that treats every round that is not `beep` as a
follow-up round must now handle `participant`. Move the server and the
mobile app to the tag `v0.14.0` together; this also brings them the 0.13.1
fix (both pin `v0.13.0` today).

## 0.13.1

**Fixed.**

- The validator refuses a `timestamp` string with an offset or without a
  zone (`lib/src/schema.dart`). A local timestamp in JSON is an ISO-8601
  string with `Z` whose fields are the wall-clock time
  (`docs/design/time-model.md` §3.1). Before 0.13.1 the parser moved a
  string with an offset to UTC, and read a string without a zone in the zone
  of the host process. Both gave a wrong local time and no error. Now the
  error is `inputInvalid` (or `outputInvalid`) with the field path and the
  message `expected timestamp (ISO-8601 with Z)`. A string that does not
  parse keeps the message `expected timestamp (ISO-8601)`. An integer and a
  double are accepted as before.
- Doc comments: the example value in `lib/src/local_time.dart` is
  `1792911600` (was `1793775600`, which is 2026-11-04 07:00); a duplicate
  line in `lib/src/contracts/scheduling.dart` is removed.

**Compatibility.** No contract version changes. The two hosts send
`isoUtc(LocalTimeCodec.toLocal(instant, zone))`, which ends with `Z`, so a
host of 0.13.0 needs no change. Move the server and the mobile app to the
tag `v0.13.1` together, before their releases.

## 0.13.0

Local time in the scripts (`docs/design/time-model.md`; the authority is
`nasp_waves_server/docs/design/time-model.md`). A script can now schedule
"07:00" and get 07:00 on the clock of the participant in any zone, before
and after a DST change, with the same result on the server and on the phone.

**Breaking.** Contract v3 for the bundle kinds (`scheduling`,
`question_selection`, `follow_up`) and contract v2 for the branch kinds
(`question_follow_up`, `question_dynamic`).

- Every `timestamp` of every contract is **local epoch seconds** in the zone
  of the run: the epoch seconds of the wall-clock time read as if it were
  UTC (`2026-10-25 07:00` is `1792911600` in any zone). The host converts
  each input with `LocalTimeCodec.toLocal` and each output with
  `LocalTimeCodec.toInstant`. The marshaller does not change.
- `scheduling`: `study.timezone` is renamed `study.zone`.
- `question_selection`: `study.zone` is added (required). The v2 contract had
  no zone field on this kind.
- `follow_up`: a new `study` group with `zone` (required), before `settings`.
- `question_follow_up` and `question_dynamic`: a top-level `zone` (required),
  after `now`.
- `follow_up` output: `follow_up` is `{trigger_at, tag}` (a clock time) or
  `{trigger_in_seconds, tag}` (a duration from `now`; an int, min 1; the host
  adds it to the instant of `now`). A non-null `follow_up` with both or with
  neither is `outputInvalid` at the path `follow_up` with the message
  `exactly one of trigger_at and trigger_in_seconds`
  (`lib/src/output_rules.dart`).
- `zone` is a non-empty string. The runtime does not check it against the tz
  database; the host does (`LocalTimeCodec.isValidZone`).

**Added.**

- `LocalTimeCodec` (`lib/src/local_time.dart`, exported):
  `toLocal(instant, zone)`, `toInstant(local, zone)`, `isValidZone(id)`. An
  unknown zone is `ArgumentError('unknown zone: <id>')`. In a gap (a
  wall-clock time that does not exist) `toInstant` moves forward to the
  instant of the transition (`02:30` on 2026-03-29 in `Europe/Stockholm` is
  `01:00Z`); in an overlap it takes the first occurrence, the earlier instant
  (`02:30` on 2026-10-25 is `00:30Z`).
- The host helpers (`lib/src/host_helpers.dart`), in `run` and in `compile`,
  each counted as a host call: `local_time(ts)` (the table `{year, month,
  day, hour, minute, second, weekday, yday}`, weekday 1 = Monday),
  `at_clock(ts, "HH:mm")`, `add_days(ts, n)`, `add_seconds(ts, n)`. Errors:
  `<helper>: argument <i> (<name>) must be an integer`, `<helper>: argument
  <i> (<name>) is out of range`, `at_clock: expected "HH:mm"`. A float with
  no fraction counts as an integer.
- The dependency `timezone: ^0.11.0` (pure Dart) with the full tz database
  `data/latest_all.dart` (every canonical zone and every link name; about
  430 KB of tz data). The tz data rides on this tag: two hosts that pin
  `v0.13.0` convert identically.

**Migration of a v2 script.**

- A daily clock time: `trigger_at = input.now + i * 86400` (09:00 UTC every
  day) becomes `trigger_at = at_clock(add_days(input.now, i), "07:00")`
  (07:00 on the clock every day).
- The hour of a timestamp: `local_time(ts).hour` (no `os.date` in the
  sandbox).
- A follow-up after a duration: `trigger_at = input.now + 1800` becomes
  `trigger_in_seconds = 1800`. A follow-up at a clock time keeps
  `trigger_at`, now a local time (`at_clock(input.now, "20:00")`).
- `input.study.timezone` becomes `input.study.zone`.
- A host fills `study.zone` (or the top-level `zone`) and converts every
  timestamp; a v2 input is `inputInvalid`.

**Compatibility.** The marshalling, the sandbox seal, the string guards, the
budgets and the seed rules do not change. `lib/` and `test/` were formatted
with the current `dart format` in a separate commit (no code change).

## 0.12.0

The string functions that would use a Lua pattern fail with a clear error.
The Lua engine (`lua_dardo_plus`) does not support the Lua patterns. In
0.11.0 some pattern calls gave a wrong result with no error (`s:find("%d")`
and `s:match("(%a+)=(%a+)")` gave nil, `[a-z_]+` gave a wrong end position),
and `gmatch`, `gsub` with a function or a table and `reverse` gave an unclear
engine error. A script could look correct and give a wrong result.

- The rule. A text is a pattern when it contains one of `^ $ * + ? . ( ) [ ]
  % -`. `string.find(s, p, init, plain)` is allowed when `plain` is true or
  `p` is not a pattern. `string.match(s, p, init)` is allowed when `p` is not
  a pattern. `string.gsub(s, p, repl, n)` is allowed when `p` is not a pattern
  and `repl` is a string (or a number) without `%`. `string.gmatch` and
  `string.reverse` always raise an error (the engine implementation of
  `reverse` is broken). The guards apply through `string.find(...)` and
  through the method syntax `s:find(...)`; the original functions are not
  reachable from a script.
- The message form: `string.<name>: Lua patterns are not supported; use
  <hint>`. Hints: `s:find(text, init, true)` (find, match); `a loop with
  s:find(text, init, true) and s:sub(i, j)` (gmatch, gsub); `a replacement
  without %` (gsub with `%` in the replacement); `a loop with s:sub(i, i)`
  (reverse). The engine adds no line number to an error raised with
  `error()`; the function name in the message locates the call.
- `#s` on a string stays an engine error (the length operator works only on
  tables); the runtime appends `; use s:len() for the length of a string` to
  the message when the error leaves Lua (`ScriptError.message`).
- `LuaScriptRuntime.compile` and `run` both have the guards: a forbidden call
  in the top-level chunk fails `compile`; a forbidden call in the entry point
  fails `run` with a `runtime` error.
- Implementation: `lib/src/string_guards.dart` (`installStringGuards`, the
  Lua prelude `stringGuardPrelude`, the predicate `isLuaPattern`), called
  from the sandbox setup. The allowed calls run the original functions, so
  their results are the same as in 0.11.0.
- Compatibility: the five contracts are unchanged (descriptors byte-identical
  to 0.11.0). A script that used a pattern got a wrong or unpredictable
  result before and gets a script error now; the hosts handle a script
  failure with their fallback (the base questions, a bundle fallback). The
  hosts move together: the server and the mobile app pin `v0.12.0`. Search
  the stored scripts of each deployment before the release.
- `LuaScriptRuntime.version` is `0.12.0`.

## 0.11.0

A fifth script kind, `question_dynamic`, for the dynamic questions script of
a branched question (server `docs/design/dynamic-questions.md` §6). It is
never a part of a script bundle. The four other contracts are unchanged.

- `ScriptKind.questionDynamic` (id `question_dynamic`), the last value of the
  enum, and its contract `questionDynamicContract` in
  `lib/src/contracts/question_dynamic.dart`, registered in `scriptContracts`.
  Entry point `dynamic_questions(input)` (`questionDynamicEntrypoint`).
  Contract version 1 (`questionDynamicContractVersion`).
  - Input: `question {id, root_question_id, questions}` (each member has
    `id`, `role` (`root` or `follow_up`), `type`, `tags`, `position`,
    `dynamic`, the base `text` and the base `options`, each option with
    `label`, `value` and `position`), `step {index, question_ids}`,
    `signals {participant_id, answers, earlier_presentations}` (each answer
    has `question_id`, `values` and `answered_at`; each earlier presentation
    has `schedule_entry_id`, `answered_at` and `answers`), `now` and `seed`.
    Each field is required. There is no `study`, `settings` or `trigger`
    group and no `type_config`.
  - Output: `questions` (an optional, nullable list; each item has `id` and
    the optional, nullable `text`, `options` (a list of `{label, value}`, with
    no position) and `key`) and `reason` (an optional, nullable string).
    Absent, null or an empty list means "each question of the step keeps its
    base content". The output has no `type` or `type_config` field; the
    validator drops a key that the schema does not declare.
- `ScriptKind.values` now has five values. `ScriptKind.bundleParts` has three
  values and does not change.
- The `scheduling`, `question_selection`, `follow_up` and
  `question_follow_up` contracts are unchanged. The bundle kinds stay
  `io_contract_version: 2` and `question_follow_up` stays 1; their
  descriptors are byte-identical to 0.10.0.
- `LuaScriptRuntime.version` is `0.11.0`.

## 0.10.0

A fourth script kind, `question_follow_up`, for the script of a branched
question (server `docs/design/branched-questions.md` §6). It is never a part
of a script bundle. The three bundle contracts are unchanged.

- `ScriptKind.questionFollowUp` (id `question_follow_up`), the last value of
  the enum, and its contract `questionFollowUpContract` in
  `lib/src/contracts/question_follow_up.dart`, registered in
  `scriptContracts`. Entry point `follow_up_questions(input)`
  (`questionFollowUpEntrypoint`). Contract version 1
  (`questionFollowUpContractVersion`).
  - Input: `question {id, root_question_id, questions}` (each member has
    `id`, `role` (`root` or `follow_up`), `type`, `tags` and `position`),
    `signals {participant_id, answers}` (each answer has `question_id`,
    `values` and `answered_at`; an empty `values` list is a skipped
    question), `now` and `seed`. Each field is required. There is no
    `study`, `settings` or `trigger` group.
  - Output: `questions` (an optional, nullable list of `{id}`) and `reason`
    (an optional, nullable string). Absent, null or an empty list means "the
    presentation is complete". The output contains only question ids.
- `ScriptKind.bundleParts`: the kinds that are parts of a bundle, in manifest
  order (`scheduling`, `question_selection`, `follow_up`). `ScriptKind.values`
  now also contains `questionFollowUp`. A host that iterates
  `ScriptKind.values` to mean "the parts of a bundle" must change to
  `ScriptKind.bundleParts`.
- The `scheduling`, `question_selection` and `follow_up` contracts are
  unchanged. They stay `io_contract_version: 2`, and their descriptors are
  byte-identical to 0.9.0.
- `LuaScriptRuntime.version` is `0.10.0`.

## 0.9.0

Optional top-level `seed` on the `scheduling` contract. Contract versions are
unchanged — all three kinds stay `io_contract_version: 2`. A descriptor that
does not use it is byte-identical to its 0.8.0 form.

- `scheduling` input: `seed`, an optional nullable `int`, next to `now`. A
  scheduling script can read `input.seed`; the host declares the seed it gave
  the sandbox `random()`, on the same footing as `question_selection` and
  `follow_up`, where `seed` is required.
- Hosts should seed the scheduling run from the participant id and the call
  time, as they do for the other kinds (server `docs/design/scripting.md`
  §9.1). Without a seed the sandbox `random()` starts from 0, so every
  participant gets the same sequence on every run.
- No migration. A host that sends no `seed` behaves as it did in 0.8.0.

## 0.8.0

Participant-editable settings schema. Contract versions are unchanged — all
three kinds stay `io_contract_version: 2`. A descriptor that uses none of the
new keys is byte-identical to its 0.7.0 form.

API change: `Constraint.min` and `Constraint.max` are now `Object?` (a `num`
or a `String`). They were `num?`. Read a bound with the typed getters
`numMin`, `numMax`, `stringMin` and `stringMax`. Do not cast the fields.

- `Field.participantEditable` (wire key `participant_editable`, a bool).
  Absent means false. It is serialised only when true. When it is true, the
  participant can edit the settings field in the mobile app (Settings >
  Personalise).
- `SettingsEditKind` and `Field.editKind`. A participant-editable field must
  have one of six edit kinds. The kind follows from the shape of the field:

  | kind | wire shape | bounds |
  | --- | --- | --- |
  | `integer` | type `int` | numbers |
  | `decimal` | type `double` | numbers |
  | `time` | type `string`, `format: time` | `HH:mm` strings |
  | `date` | type `string`, `format: date` | `yyyy-MM-dd` strings |
  | `time_span` | type `object`, `format: time_span`, exactly the `string` fields `start` and `end`, each with `format: time` | `HH:mm` strings, applied to `start` and to `end` |
  | `date_span` | type `object`, `format: date_span`, exactly the `string` fields `start` and `end`, each with `format: date` | `yyyy-MM-dd` strings, applied to `start` and to `end` |

  `Field.editKind` returns null for all other shapes. `SettingsEditKind.wireName`
  gives the name in the first column. `SettingsEditKind.fromWireName` is the
  inverse.
- Format constants: `Field.formatTime`, `Field.formatDate`,
  `Field.formatTimeSpan` and `Field.formatDateSpan`.
- String bounds. `constraint.min` and `constraint.max` accept a number or a
  non-empty string. Any other value is a parse error:
  `"min" must be a number or a non-empty string`.
- `Field.fromJson` rejects these combinations with a path-qualified
  `FormatException`:
  - `participant_editable` that is not a bool.
  - `participant_editable: true` on a field without an edit kind.
  - A number bound on a field that is not `int` or `double`.
  - A string bound on a field that is not `time`, `date`, `time_span` or
    `date_span`.
  - `format: time_span` or `format: date_span` on a field that is not the
    span object shape.
  `format: time` and `format: date` stay advisory on other fields.
- The validator applies string bounds. It compares strings
  lexicographically, so values must use the canonical `HH:mm` or
  `yyyy-MM-dd` form. On a span it checks `start` and `end` separately and
  reports the part path (for example `rule.quiet_hours.end: must be <=
  22:00`). It does not require `start <= end`, so an overnight time span
  (22:00-06:00) is valid. Number bounds work as before.
- `LuaScriptRuntime.version` is `0.8.0`.

## 0.7.0

Additive. Contract versions are unchanged — all three kinds stay
`io_contract_version: 2`, and a descriptor that uses none of the new keys is
byte-identical to its 0.6.0 form.

- `Field.fromQuestion` (wire key `from_question`, a non-empty string). Names
  the enrolment question whose answer seeds a settings field. Advisory: the
  validator never reads it; the server's settings derivation does, to build a
  participant's script settings from the enrolment questionnaire.
- `Field.format` (wire key `format`, a non-empty string). A display hint for a
  `string` field, so a client form can show the right control. Documented
  values: `time` (an `HH:mm` clock time) and `date` (a `yyyy-MM-dd` calendar
  date). Advisory: read by client forms, never by the validator.
- `LuaScriptRuntime.version` now equals the package version. It was stuck at
  `0.1.0` while the package was at `0.6.0`, which made a host's
  `runtime_min_version` check wrong. `test/version_test.dart` reads
  `pubspec.yaml` and asserts the two agree, so they cannot drift again.

## 0.6.0 — BREAKING — contract v2

`io_contract_version` is now **2** for all three kinds (`scheduling`,
`question_selection`, `follow_up`). Every input is grouped by provenance so
the structure itself documents where a value comes from:

- `study` — study variables, the same for every participant of the study.
- `settings` — the resolved script settings (participant-scope override wins
  over study scope). Shape unchanged.
- `signals` — participant-specific data the script analyses. Anything
  participant-specific is a signal; device telemetry (location, usage) will be
  added here later, additively.
- top-level — invocation values from the host (`now`, `seed`, `trigger`).

Output schemas, round and schedule-entry shapes are unchanged. A v1-shaped
input now fails validation with a path-qualified `inputInvalid` error at the
first missing group (`study` or `signals`).

v1 → v2 path mapping:

| kind | v1 | v2 |
| --- | --- | --- |
| scheduling | `timezone` | `study.timezone` |
| scheduling | `study_window.start` / `.end` | `study.window.start` / `.end` |
| scheduling | `horizon_days` | `study.horizon_days` |
| scheduling | `study_length_days` | `study.length_days` |
| scheduling | `settings` | `settings` (unchanged) |
| scheduling | — | `signals.participant_id` (**new**, non-empty string) |
| scheduling | `enrolment_date` | `signals.enrolment_date` |
| scheduling | `now` | `now` (unchanged) |
| question_selection | `question_sets` | `study.question_sets` |
| question_selection | `questions` | `study.questions` |
| question_selection | `settings` | `settings` (unchanged, optional) |
| question_selection | `participant_id` | `signals.participant_id` |
| question_selection | `answer_history` | `signals.answers` |
| question_selection | `trigger`, `seed` | `trigger`, `seed` (unchanged) |
| follow_up | `settings` | `settings` (unchanged, optional) |
| follow_up | `participant_id` | `signals.participant_id` |
| follow_up | `current_round` | `signals.current_round` |
| follow_up | `recent_rounds` | `signals.recent_rounds` |
| follow_up | `schedule` | `signals.schedule` |
| follow_up | `now`, `seed` | `now`, `seed` (unchanged) |

`follow_up` has no `study` group (it has no study-level values today; adding
one later is additive).

Additive:

- `Field.description`: optional, author-facing prose serialised as
  `description` in the descriptor wire shape. Advisory — the validator never
  reads it. Meant for bundle-declared settings schemas; the kind contracts
  leave it unset (their documentation lives in the server's input
  reference). Fields without a description serialise byte-identically to
  0.5.0.

## 0.5.0

- `settings` (the resolved schedule settings) is accepted, optionally, on the
  `question_selection` and `follow_up` inputs.

## 0.4.0

- Schema wire-shape parsing: `Schema.fromJson`, `TypeSpec.fromJson`,
  `Field.fromJson`, `Constraint.fromJson` — the exact inverse of the frozen
  descriptor JSON, with path-qualified `FormatException`s on malformed input.
  Enables hosts to accept and validate against bundle-declared schemas
  (script settings schemas).
- `Field.defaultValue`: optional, additive `default` key in the descriptor
  wire shape. Advisory (form prefill); the validator does not apply it.
  Descriptors without defaults serialise byte-identically to 0.3.0.

## 0.3.0

- `follow_up` script kind and I/O contract (entrypoint `follow_up`).

## 0.2.0

- Optional `study_length_days` on the `scheduling` input.
## 0.1.0

- Initial release, extracted from the `nasp_waves_server` workspace bootstrap.
- `LuaScriptRuntime` (run + compile) over `lua_dardo_plus` 0.3.0 (Lua 5.3):
  explicit sandbox, host `now()`/`random(seed)`/`log()`, budgets
  (host-call count, wall-clock, trace cap, output-size ceiling).
- `ScriptKind` / `ScriptError` taxonomy (compile, inputInvalid, runtime,
  outputInvalid, budgetExceeded, contractUnsupported), part-attributed and
  path-qualified.
- Schema type + validator with contract-descriptor JSON serialisation.
- `scheduling` and `question_selection` contracts, `io_contract_version = 1`,
  entrypoints `schedule` / `select_questions`.
- Total, lossless Dart↔Lua marshalling (timestamps ↔ epoch seconds,
  int/double preserved).
- Conformance suite: 22 tests (determinism, sandbox, error taxonomy, budgets,
  no-Flutter/FFI dependency guard).
