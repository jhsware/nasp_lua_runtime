# Changelog

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
