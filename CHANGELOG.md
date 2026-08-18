# Changelog

## 0.4.0

- Schema wire-shape parsing: `Schema.fromJson`, `TypeSpec.fromJson`,
  `Field.fromJson`, `Constraint.fromJson` — the exact inverse of the frozen
  descriptor JSON, with path-qualified `FormatException`s on malformed input.
  Enables hosts to accept and validate against bundle-declared schemas
  (script settings schemas).
- `Field.defaultValue`: optional, additive `default` key in the descriptor
  wire shape. Advisory (form prefill); the validator does not apply it.
  Descriptors without defaults serialise byte-identically to 0.3.0.

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
