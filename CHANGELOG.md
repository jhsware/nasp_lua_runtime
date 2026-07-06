# Changelog

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
