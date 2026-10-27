# nasp_lua_runtime — Mandatory and optional questions in the contracts

> **Version:** 1.0
> **Date:** 2026-10-27
> **Status:** Built: runtime 0.15.0 (tag `v0.15.0`). This document
> describes the package as built; §"Differences from 0.3" records each
> change from the design of version 0.3.
> **Changed in 1.0 (2026-10-27):** as built; §9 lists the changes.
> **Authority:** `nasp_waves_server/docs/design/mandatory-questions.md`
> (0.3, the design of the four repositories). This document describes the
> part that lives in this package: the contract fields, the declaration of
> a branching script, the version and the tests. "server §n" is a section
> of the authority.

---

## 1. Purpose

A question is optional by default; the operator, a study rule or a script
can make it mandatory; a participant skips an optional question, and the
skip is an answer with no value (server §1, §9). The scripts must see the
setting of each question, and two scripts must be able to raise it. A
branching script must be able to say that it needs a value for the root
question (server §8). This package gives the fields and the declaration;
the hosts fill the fields and read the declaration.

## 2. The rule

Every change is **additive**: each new field is `required: false,
nullable: true`, no `io_contract_version` moves, and a descriptor of a
host that does not use a field stays byte-identical in the fields it had
(the precedents of `seed` in 0.9.0 and `trigger.type` in 0.14.0). A script
written for 0.14.0 runs unchanged: the validator drops an undeclared
output key and an absent input key is absent.

A skipped answer is what it is today: an empty `values` list in the
answers of `question_follow_up`, `question_dynamic` and `follow_up`
(server D7). No field says "skipped"; the answer shapes do not change.

The package carries no prose for a field (`schema_test.dart`, "no contract
field carries a description"); the prose is the server's input reference
(server §7, §14).

## 3. The fields

### 3.1 `question_selection` (`lib/src/contracts/question_selection.dart`, stays version 3)

| Path | Type | Side | Meaning (the server's prose) |
|---|---|---|---|
| `study.questions[].mandatory` | bool, optional, nullable | input | The effective setting of the catalog question (server §6). Absent from an older host. |
| `items[].mandatory` | bool, optional, nullable | output | `true` makes the item mandatory in this round: a question, every member of a set, or the root of a branched question. `false` or absent leaves the effective value (server D6). |

### 3.2 `question_follow_up` (`lib/src/contracts/question_follow_up.dart`, stays version 2)

| Path | Type | Side | Meaning |
|---|---|---|---|
| `question.questions[].mandatory` | bool, optional, nullable | input | The effective setting of the member. |
| `questions[].mandatory` | bool, optional, nullable | output | `true` makes that follow-up question mandatory in this presentation. |

The library comment of the file keeps "A skipped question has an empty
`values` list" and adds: "The root entry `answers[1]` can be a skipped
question when the root is optional."

### 3.3 `question_dynamic` (`lib/src/contracts/question_dynamic.dart`, stays version 2)

| Path | Type | Side | Meaning |
|---|---|---|---|
| `question.questions[].mandatory` | bool, optional, nullable | input | The effective setting of the member. |

No output change: the dynamic script rewords, it does not select.

### 3.4 `follow_up` and `scheduling`

No change.

### 3.5 Field order

A new field goes **last** in its object, so that the top-level and nested
orders of the existing fields do not move: `mandatory` after
`set_position` in the catalog question, after `position` in a member of
`question_follow_up`, after `options` in a member of `question_dynamic`,
after `kind` in a selection item and after `id` in a follow-up output
item. `test/mandatory_fields_test.dart` asserts the full key order of each
of these objects; `runtime_test.dart` (`contract v3`) asserts the
top-level names.

An output item that leaves `mandatory` nil comes back with
`mandatory: null`, the marshaller's rule for every nullable output field
(Differences 6).

## 4. The declaration of a branching script

A branching script that needs a value for the root question declares it
with one global boolean at the top level of the chunk (server §8.1):

```lua
requires_root_answer = true
```

The name is the same in Lua, on the wire and in Dart (server D8). The
package reads it with a method of `LuaScriptRuntime` (`lib/src/vm.dart`),
synchronous like `compile` and `run`:

```dart
ScriptDeclarationsResult declarations(ScriptKind kind, String source);
```

- It runs like `compile`: the same sandbox, the stub `now`, `random`,
  `log`, the real host helpers, `loadString`, the chunk, the entry-point
  check (one private helper, `_loadChecked`, serves both). Then it reads
  the global `requires_root_answer`.
- `ScriptDeclarationsResult` has `error: ScriptError?` (the error of
  `compile`, or the one below), `declarations: ScriptDeclarations` (the
  defaults when `error` is set) and `ok`. `ScriptDeclarations` has
  `requiresRootAnswer: bool` (default `false`); `toJson()` gives
  `{'requires_root_answer': bool}`. Both are exported.
- The global is optional: absent or `nil` is `false`. A value that is
  not a boolean is a `ScriptError(type: compile, part: kind, message:
  'requires_root_answer must be a boolean')` with no `path`.
- The declaration has a meaning for `ScriptKind.questionFollowUp` only.
  For each other kind the method returns `false` and does not read the
  global, so that an unrelated script with a global of that name does not
  fail.
- `compile` does not change: a host that does not need the declaration
  pays nothing. `run` does not read the global; the declaration never
  changes what a run does.

The runtime does not enforce the declaration. The server compares it with
the effective setting of the root and gives the warning (server §8.3). The
mobile app does not call `declarations`.

## 5. The version

Runtime **0.15.0**, tag `v0.15.0`: `pubspec.yaml` and
`LuaScriptRuntime.version` together (`version_test.dart`). No contract
version moves: the bundle kinds stay at 3, the branch kinds at 2. The
hosts move their pins together (server D10: the runtime tag first, then
the server with the backend app, then the mobile app).

`branchRuntimeMinVersions` of the server does not change: a branched
question that uses `questions[].mandatory` in its output runs on a phone
with runtime 0.14.0, which drops the key and presents the follow-up as
optional. That is the additive path (server §13).

The CHANGELOG entry (`## 0.15.0`, which also takes the documentation entry
that was under `## Unreleased`): an intro, `**Added.**` with the fields of
§3 and the method of §4, `**Documentation.**`, and `**Compatibility.**`:
"No contract version changes: the bundle kinds stay at 3, the branch kinds
at 2. A script written for 0.14.0 runs unchanged. Move the server and the
mobile app to the tag `v0.15.0` together." README: the "Contract v3"
section has the fields; a new section "Script declarations" has
`requires_root_answer`; "Consuming" pins `ref: v0.15.0`.

## 6. Tests

The pattern of `round_type_test.dart` and
`question_follow_up_contract_test.dart`:

| Test file | Covers |
|---|---|
| `test/mandatory_fields_test.dart` (new) | For each kind of §3: the descriptor lists the field as optional, nullable, of type `bool`, without a description, and as the last key of its object (the full key order is asserted, §3.5); `question_dynamic` has no output `mandatory`; an input without the field validates (backward compatible); an input with `mandatory: true` validates and a Lua script reads it (`log()` + `r.trace`); `mandatory: "yes"` is `inputInvalid` at the path; an output item with `mandatory = true` comes back with the key, and one without it comes back with `mandatory: null`; an output item with `mandatory = "yes"` is `outputInvalid` at `items[0].mandatory` / `questions[0].mandatory`; a skipped root (empty `values`) is valid. |
| `test/declarations_test.dart` (new) | No global → false; `requires_root_answer = true` → true; `= false` and `= nil` → false; `= 1`, `= "true"`, `= {}` → the compile error with the message and `part` the kind; the global in a `question_selection` script → false and no error; a syntax error is the `compile` error of `compile`; a runtime error of the chunk is `runtime`; a chunk without the entry point is the `runtime` entry-point error; `compile` and `run` ignore the declaration; `toJson()`. |
| `test/question_follow_up_contract_test.dart` | The existing test "an answer with an empty values list is valid (a skipped question)" stands and is the rule for the root too. Two output expectations now include `mandatory: null` (Differences 6). |
| `test/round_type_test.dart` | One output expectation now includes `mandatory: null` (Differences 6). |
| `test/runtime_test.dart` | The `contract v3` group still passes: the field orders of the existing fields do not move. |
| `test/schema_test.dart` | The no-description rule still passes (no `description` on the new fields); the 0.7.0 byte-identical descriptor test still passes. |
| `test/version_test.dart` | `0.15.0`. |

The byte-identical fixture is the server's
(`nasp_waves_server/test/fixtures/device_script_context.json`, version 9
after this work); this package has no copy.

## 7. What does not change

The sandbox, the budgets, the host helpers, the `LocalTimeCodec`, the
string guards, the output rules, the marshaller and the answer shapes of
every contract. `run` and `compile` keep their signatures.

## 8. Open points

1. Should `declarations` replace `compile` (one method that returns the
   error and the declarations)? As built (0.15.0), `compile` stays and
   both share one private helper (`_loadChecked`), so the mobile app does
   not change its call; the server calls `declarations` where it calls
   `compile` today for a branching script. Open for a later release.

## Differences from 0.3

What the build (runtime 0.15.0) changed from version 0.3 of this design:

1. **`declarations` is synchronous**, like `compile` and `run`:
   `ScriptDeclarationsResult declarations(ScriptKind kind, String source)`.
   0.3 had a `Future`; nothing in the engine is asynchronous.
2. **The error type of a non-boolean declaration is `compile`**, as 0.3
   says. It is a new use of `ScriptErrorType.compile`: before 0.15.0 that
   type meant a `loadString` failure only. Its `path` is null.
3. **`ScriptDeclarationsResult` mirrors `ScriptRunResult`** (there is no
   compile result type): `error`, `declarations` and an `ok` getter. Both
   classes have `const` constructors with the defaults (`error: null`,
   `ScriptDeclarations()`).
4. **One private helper for `compile` and `declarations`**:
   `_loadChecked(kind, source)` returns `({ScriptError? error, LuaState?
   state})`; `compile` is `_loadChecked(kind, source).error`, with the same
   types and messages as before.
5. **The private engine helpers moved** (`_sealSandbox`, `_luaMessage`,
   `_withHints`) to `lib/src/vm_support.dart`, a `part of 'vm.dart'`, so
   that `vm.dart` stays under 500 lines. No behaviour change.
6. **A nil output `mandatory` comes back as `null`.** The marshaller
   (`lib/src/marshal.dart`) writes a nullable output field that the script
   leaves nil as `null`, as it does for `reason`. So an output item without
   `mandatory` is `{id, kind, mandatory: null}` (`question_selection`) or
   `{id, mandatory: null}` (`question_follow_up`), not an item without the
   key. Three existing tests moved to the new shape
   (`question_follow_up_contract_test.dart`: "returns the selected
   questions and the reason", "the script reads the question group and the
   answer values"; `round_type_test.dart`: "a participant round can pick
   its own questions"). A host treats `null` as absent. The marshaller does
   not change.
7. **The nested field orders are asserted in
   `test/mandatory_fields_test.dart`**, not in `runtime_test.dart` (whose
   `contract v3` group asserts the top-level names only). The test asserts
   the full key order of each object that gained the field.
8. **The descriptor wire name of the type is `bool`** (`TypeSpec.boolean()`
   serialises as `{'type': 'bool'}`).

## 9. Changes

| Version | Date | Changes |
|---|---|---|
| 0.1 | 2026-10-27 | The first design. |
| 0.2 | 2026-10-27 | Server D7: the `skipped` fields removed from every answer shape (§2, §3); `follow_up` unchanged; the shared answer object of 0.1 §3.3 dropped with them. Server D8: the declaration is the global `requires_root_answer` (§4); the error message follows. |
| 0.3 | 2026-10-27 | Server 0.3: Sebastian confirmed D1 to D6 and D10. No change to the design. |
| 1.0 | 2026-10-27 | As built in runtime 0.15.0: §4 synchronous `declarations` and the final names; §3.5 and §6 the tests as built; §8 the open point answered for now; the section "Differences from 0.3". |
