# nasp_lua_runtime — Mandatory and optional questions in the contracts

> **Version:** 0.1
> **Date:** 2026-10-27
> **Status:** Design. Nothing is built. The work is runtime 0.15.0; when it
> is built, a §"Differences from 0.1" records each change from this version.
> **Authority:** `nasp_waves_server/docs/design/mandatory-questions.md`
> (the design of the four repositories). This document describes the part
> that lives in this package: the contract fields, the declaration of a
> branching script, the version and the tests. "server §n" is a section of
> the authority.

---

## 1. Purpose

A question is optional by default; the operator, a study rule or a script
can make it mandatory; a participant skips an optional question, and the
skip is recorded (server §1). The scripts must see the setting of each
question and the skips of the participant, and two scripts must be able
to raise the setting. A branching script must be able to say that it needs
a value for the root question (server §8). This package gives the fields
and the declaration; the hosts fill the fields and read the declaration.

## 2. The rule

Every change is **additive**: each new field is `required: false,
nullable: true`, no `io_contract_version` moves, and a descriptor of a
host that does not use a field stays byte-identical in the fields it had
(the precedents of `seed` in 0.9.0 and `trigger.type` in 0.14.0). A script
written for 0.14.0 runs unchanged: the validator drops an undeclared
output key and an absent input key is absent.

The package carries no prose for a field (`schema_test.dart`, "no contract
field carries a description"); the prose is the server's input reference
(server §7, §14).

## 3. The fields

### 3.1 `question_selection` (`lib/src/contracts/question_selection.dart`, stays version 3)

| Path | Type | Side | Meaning (the server's prose) |
|---|---|---|---|
| `study.questions[].mandatory` | bool, optional, nullable | input | The effective setting of the catalog question (server §6). Absent from an older host. |
| `signals.answers[].skipped` | bool, optional, nullable | input | True when that answer was a skip; for a branched presentation, true when the root was skipped. |
| `items[].mandatory` | bool, optional, nullable | output | `true` makes the item mandatory in this round: a question, every member of a set, or the root of a branched question. `false` or absent leaves the effective value (server D6). |

### 3.2 `question_follow_up` (`lib/src/contracts/question_follow_up.dart`, stays version 2)

| Path | Type | Side | Meaning |
|---|---|---|---|
| `question.questions[].mandatory` | bool, optional, nullable | input | The effective setting of the member. |
| `signals.answers[].skipped` | bool, optional, nullable | input | True when the participant skipped the question. `values` is then empty. The root entry `answers[1]` can be skipped (server §7.3). |
| `questions[].mandatory` | bool, optional, nullable | output | `true` makes that follow-up question mandatory in this presentation. |

The library comment of the file changes: "A skipped question has an empty
`values` list" becomes "A skipped question has `skipped` true and an empty
`values` list; a host older than the field sends the empty list only."

### 3.3 `question_dynamic` (`lib/src/contracts/question_dynamic.dart`, stays version 2)

| Path | Type | Side | Meaning |
|---|---|---|---|
| `question.questions[].mandatory` | bool, optional, nullable | input | The effective setting of the member. |
| `signals.answers[].skipped` | bool, optional, nullable | input | As in §3.2. |
| `signals.earlier_presentations[].answers[].skipped` | bool, optional, nullable | input | As in §3.2, for an earlier presentation. |

No output change: the dynamic script rewords, it does not select.

The shared answer shape `_answer()` (`question_dynamic.dart`) gets the
field once; `question_follow_up.dart` and `follow_up.dart` declare the
same answer object, so each file gets the field (the files do not share
code today; a shared `answerSpec()` in a new `lib/src/contracts/answers.dart`
is the better home and is part of this work).

### 3.4 `follow_up` (`lib/src/contracts/follow_up.dart`, stays version 3)

| Path | Type | Side | Meaning |
|---|---|---|---|
| `signals.current_round.answers[].skipped` | bool, optional, nullable | input | As in §3.2. |
| `signals.recent_rounds[].answers[].skipped` | bool, optional, nullable | input | As in §3.2. |

### 3.5 `scheduling`

No change.

### 3.6 Field order

A new field goes **last** in its object, so that the top-level and nested
orders that `runtime_test.dart` asserts (`contract v3`) do not move:
`mandatory` after `set_position` in the catalog question, after `position`
in a member, after `kind` in a selection item and after `id` in a
follow-up output item; `skipped` after `answered_at` in an answer.

## 4. The declaration of a branching script

A branching script that needs a value for the root question declares it
with a global table at the top level of the chunk (server §8.1):

```lua
script_requirements = { root_answer = true }
```

The package reads it with a new method of `LuaScriptRuntime`
(`lib/src/vm.dart`):

```dart
Future<ScriptDeclarationsResult> declarations(ScriptKind kind, String source);
```

- It runs like `compile`: the same sandbox, the stub `now`, `random`,
  `log`, the real host helpers, `loadString`, the chunk, the entry-point
  check. Then it reads the global `script_requirements`.
- `ScriptDeclarationsResult` has `error: ScriptError?` (the error of
  `compile`, or the one below) and `declarations: ScriptDeclarations`.
  `ScriptDeclarations` has `requiresRootAnswer: bool` (default `false`);
  `toJson()` gives `{'requires_root_answer': bool}`.
- The global is optional: absent or `nil` is `requiresRootAnswer` false.
  A table without `root_answer` is false. A `root_answer` that is not a
  boolean is a `ScriptError(type: compile, part: kind, message:
  'script_requirements.root_answer must be a boolean')`. A
  `script_requirements` that is not a table is
  `'script_requirements must be a table'`. Other keys are ignored, so
  that a later version can add one.
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
optional. A branch script that reads `answers[].skipped` on such a phone
reads `nil`. That is the additive path (server §13).

The CHANGELOG entry (`## 0.15.0`): an intro, `**Added.**` with the fields
of §3 and the method of §4, and `**Compatibility.**`: "No contract version
changes. Move the server and the mobile app to the tag `v0.15.0` together."
README: the "Contract v3" section gets the fields; a new short section
"Script requirements" gets the declaration.

## 6. Tests

The pattern of `round_type_test.dart` and
`question_follow_up_contract_test.dart`:

| Test file | Covers |
|---|---|
| `test/mandatory_fields_test.dart` (new) | For each kind of §3: the descriptor lists the field as optional and nullable, in the position of §3.6; an input without the field validates (backward compatible); an input with `mandatory: true` / `skipped: true` validates and a Lua script reads it (`log()` + `r.trace`); `mandatory: "yes"` is `inputInvalid` at the path; an output item with `mandatory = true` comes back with the key; an output item with `mandatory = "yes"` is `outputInvalid` at `items[0].mandatory`. |
| `test/declarations_test.dart` (new) | No global → false; `{ root_answer = true }` → true; `{ root_answer = false }` → false; `{}` → false; `root_answer = 1` → the compile error with the message; `script_requirements = 1` → its message; the global in a `question_selection` script → false and no error; a compile error of the chunk is returned; the entry-point check runs. |
| `test/runtime_test.dart` | The `contract v3` group still passes: the field orders of the existing fields do not move. |
| `test/schema_test.dart` | The no-description rule still passes (no `description` on the new fields); the 0.7.0 byte-identical descriptor test still passes. |
| `test/version_test.dart` | `0.15.0`. |

The byte-identical fixture is the server's
(`nasp_waves_server/test/fixtures/device_script_context.json`, version 9
after this work); this package has no copy.

## 7. What does not change

The sandbox, the budgets, the host helpers, the `LocalTimeCodec`, the
string guards, the output rules and the marshaller. `run` and `compile`
keep their signatures.

## 8. Open points

1. Should `declarations` replace `compile` (one method that returns the
   error and the declarations)? The design keeps `compile` so that the
   mobile app does not change its call; the server calls `declarations`
   where it calls `compile` today for a branching script.
2. A shared answer object across the three contract files (§3.3): the
   design proposes `lib/src/contracts/answers.dart`; the descriptors do
   not change by it.
