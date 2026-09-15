# Changelog

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
