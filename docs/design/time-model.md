# nasp_lua_runtime — Time model: local time in the scripts

> **Version:** 0.1
> **Date:** 2026-10-24
> **Status:** Draft — design. The planner task "Runtime 0.13.0: contract v3 —
> local time, LocalTimeCodec, the host helpers, the duration output of
> follow_up, the tz database pin" builds it. That task sets this document to
> 1.0 and records each difference from the design.
> **Authority:** `nasp_waves_server/docs/design/time-model.md` (the time
> model of the four repositories). This document describes the part that
> lives in this package.

---

## 1. Purpose

A script must schedule "07:00" and get 07:00 on the clock of the participant,
before and after a DST change, in any zone. The sandbox has no `os`, no tz
database and no helper, so a script cannot compute a local hour from an
instant (server time-model.md §1; analysis findings R-2, R-3, R-4). The
runtime therefore changes what a `timestamp` means, gives the hosts one
codec, and gives the scripts four helpers.

## 2. The rule (server time-model.md R5, D8)

**The script sees local time only.** Every timestamp of every contract is
**local epoch seconds** in the zone of the run: a wall-clock time encoded as
the epoch seconds of that wall-clock time read as if it were UTC.
`2026-10-25 07:00` is `1793775600` in any zone. The host converts in both
directions. The script keeps integer arithmetic.

The host builds the `seed` from the UTC string of the real `now`, before
the conversion. The seed rules do not change.

## 3. What this package provides

### 3.1 `LocalTimeCodec`

One class, byte-identical on both hosts, in `lib/src/local_time.dart`:

- `LocalTimeCodec.toLocal(DateTime instant, String zone) -> DateTime`: a
  `DateTime` with `isUtc` true whose fields are the wall-clock time of
  `instant` in `zone`. The marshaller pushes it to Lua as its epoch seconds,
  which are the local epoch seconds. No change in `marshal.dart`.
- `LocalTimeCodec.toInstant(DateTime local, String zone) -> DateTime`: the
  instant of the wall-clock time of `local` in `zone`, with the gap and
  overlap rules of §4.
- `LocalTimeCodec.isValidZone(String id) -> bool`: true when `id` is in the
  bundled tz database.

The codec uses `package:timezone` and initialises the bundled database
once (`initializeTimeZones` or the trimmed `latest_10y` set; the task
measures the size for the mobile app and records the choice). The pin of
the tz data rides on the runtime tag: both hosts that pin the same runtime
tag resolve identically.

The JSON form of a local timestamp is an ISO-8601 string with `Z` whose
fields are the wall-clock time (`2026-10-25T07:00:00.000Z` means 07:00 on
the clock of the run). The schema's `timestamp` parser already reads this
form. A host writes it with `isoUtc(codec.toLocal(instant, zone))`.

### 3.2 The host helpers

Four helpers in the sandbox, next to `now()`, `random()` and `log()`
(`vm.dart`, registered in both `run` and `compile`). They are pure
functions on integers; the tz database is not involved.

| Helper | Returns |
|---|---|
| `local_time(ts)` | the table `{year, month, day, hour, minute, second, weekday, yday}`; `weekday` is 1 = Monday to 7 = Sunday; `yday` is 1 to 366 |
| `at_clock(ts, "HH:mm")` | the local epoch second of that clock time on the day of `ts`; a malformed clock string is a Lua error `at_clock: expected "HH:mm"` |
| `add_days(ts, n)` | `ts` plus `n` days of 86400 seconds (the same clock time `n` days later, because the numbers are local); `n` may be negative |
| `add_seconds(ts, n)` | `ts + n` |

`now()` returns the local epoch second of the input `now` (the host passes
the converted value as the `now` argument of `run`).

Each helper counts as a host call for the budget, as the three existing
helpers do.

### 3.3 The contracts

- `scheduling`, `question_selection`, `follow_up`: `io_contract_version` 3.
- `question_follow_up`, `question_dynamic`: `io_contract_version` 2 (they
  carry `answered_at` and `now`).
- `study.timezone` is renamed `study.zone` on `scheduling` and on
  `question_selection` (where the `study` group exists), with the meaning
  "the IANA zone this run resolves local times in". `follow_up` gets a
  `study` group with `zone` only. The branch kinds get `zone` at the top
  level next to `now`.
- `follow_up` output: `follow_up` is `{trigger_at, tag}` or
  `{trigger_in_seconds, tag}`. `trigger_in_seconds` is an integer, min 1.
  Both present or both absent in a non-null `follow_up` is `outputInvalid`
  with the path `follow_up`.
- The doc comment of every `timestamp` field says "local epoch seconds in
  the zone of the run". The schema descriptors carry no prose (the
  no-`description` rule of the contract fields stays); the prose is in the
  server's input reference.

### 3.4 The version

`LuaScriptRuntime.version` and `pubspec.yaml` become `0.13.0`. The tag is
`v0.13.0`. The server and the mobile app pin it.

## 4. The DST rules (server time-model.md §9)

`LocalTimeCodec.toInstant` applies:

- **A gap.** A clock time that does not exist (`02:30` on 2026-03-29 in
  `Europe/Stockholm`) moves forward to the first valid instant (the same
  instant as `03:00` local).
- **An overlap.** A clock time that exists twice (`02:30` on 2026-10-25)
  takes the first occurrence (offset `+02:00`).
- **A recurring clock time** keeps its clock time across a DST date. The
  helpers make this automatic: `at_clock(add_days(ts, 1), "07:00")` is
  07:00 on the next day whatever the zone does.
- **A duration** keeps its length. `trigger_in_seconds` resolves through the
  instant of `now`.

## 5. The fixtures

`test/local_time_test.dart` and `test/host_helpers_test.dart` cover, with
the zone `Europe/Stockholm` and the two 2026 changes (2026-03-29 02:00 →
03:00; 2026-10-25 03:00 → 02:00):

- `toLocal` and `toInstant` round trips on a plain day, on the two DST days,
  on the gap and on the overlap;
- `toLocal` in `Asia/Tokyo` and `America/New_York` (no DST and a different
  DST calendar);
- an unknown zone is an `ArgumentError`;
- `local_time` on the four weekday boundaries and on a leap day;
- `at_clock` on the DST days (the number is local, so no jump);
- `add_days` across a month end and a year end;
- a scheduling script that returns `at_clock(add_days(input.now, i), "07:00")`
  for seven days across 2026-10-25, converted with the codec: the instants
  are 05:00Z before and 06:00Z after the change;
- a `follow_up` script that returns `trigger_in_seconds = 1800` at 02:45
  local on 2026-10-25: the host-resolved instant is 30 minutes after `now`.

## 6. What does not change

- `marshal.dart`: a `DateTime` is pushed as its epoch seconds; a Lua number
  is read as epoch seconds into a `DateTime` with `isUtc` true.
- The sandbox seal, the string guards, the budget.
- The validator: `timestamp` accepts an ISO string, an integer or a double.
- The `seed` rules.
