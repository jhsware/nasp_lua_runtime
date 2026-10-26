# nasp_lua_runtime — Time model: local time in the scripts

> **Version:** 1.1
> **Date:** 2026-10-26
> **Status:** Describes the code as built (runtime 0.13.1, tag `v0.13.1`).
> Version 0.1 was the design; §8 records each difference from it.
> **Changed in 1.1:** the validator refuses a timestamp string with an
> offset or without a zone (§3.1, §6).
> **Authority:** `nasp_waves_server/docs/design/time-model.md` (the time
> model of the four repositories). This document describes the part that
> lives in this package.

---

## 1. Purpose

A script must schedule "07:00" and get 07:00 on the clock of the participant,
before and after a DST change, in any zone. Before 0.13.0 the sandbox had no
`os`, no tz database and no helper, so a script could not compute a local
hour from an instant (server time-model.md §1; analysis findings R-2, R-3,
R-4). The runtime therefore changes what a `timestamp` means, gives the
hosts one codec, and gives the scripts four helpers.

## 2. The rule (server time-model.md R5, D8)

**The script sees local time only.** Every timestamp of every contract is
**local epoch seconds** in the zone of the run: a wall-clock time encoded as
the epoch seconds of that wall-clock time read as if it were UTC.
`2026-10-25 07:00` is `1792911600` in any zone. The host converts in both
directions. The script keeps integer arithmetic.

The host builds the `seed` from the UTC string of the real `now`, before
the conversion. The seed rules do not change.

## 3. What this package provides

### 3.1 `LocalTimeCodec`

One class, the same on both hosts, in `lib/src/local_time.dart` (exported
from `package:nasp_lua_runtime/nasp_lua_runtime.dart`):

- `LocalTimeCodec.toLocal(DateTime instant, String zone) -> DateTime`: a
  `DateTime` with `isUtc` true whose fields are the wall-clock time of
  `instant` in `zone`. The marshaller pushes it to Lua as its epoch seconds,
  which are the local epoch seconds. No change in `marshal.dart`.
- `LocalTimeCodec.toInstant(DateTime local, String zone) -> DateTime`: the
  instant (UTC) of the wall-clock time of `local` in `zone`, with the gap and
  overlap rules of §4. The fields of `local` are read; its `isUtc` flag is
  not used.
- `LocalTimeCodec.isValidZone(String id) -> bool`: true when `id` is in the
  bundled tz database. The empty string is false.
- An unknown zone in `toLocal` or `toInstant` throws
  `ArgumentError('unknown zone: <id>')`.

The tz database is `package:timezone` `^0.11.0` with the full data set
`data/latest_all.dart` (every canonical zone and every link name, with the
full history), loaded into the global database of `package:timezone` on the
first call of the codec. Measured with timezone 0.11.2:

| variant | `.tzf` data | `.dart` file |
|---|---|---|
| `latest_all` (used) | 441,320 B | 1,937,436 B |
| `latest` | 257,744 B | 1,131,735 B |
| `latest_10y` | 66,768 B | 293,565 B |

`latest_all` adds about 375 KB to an app compared with `latest_10y`. It is
the choice because a phone can report a link name (`Europe/Kiev`,
`US/Eastern`) and because `latest_10y` has only a window of years around the
data release, which a study that runs later can leave. A host must not load
a smaller variant after the codec. The pin of the tz data rides on the
runtime tag: both hosts that pin the same runtime tag resolve identically.

The JSON form of a local timestamp is an ISO-8601 string with `Z` whose
fields are the wall-clock time (`2026-10-25T07:00:00.000Z` means 07:00 on
the clock of the run). The schema's `timestamp` parser reads this form. A
host writes it with `isoUtc(LocalTimeCodec.toLocal(instant, zone))`.

Since 0.13.1 the parser refuses a string with an offset (`+02:00`, also
`+00:00`) or without a zone, with the message `expected timestamp (ISO-8601
with Z)` and the field path (`inputInvalid` on the input, `outputInvalid` on
the output). `DateTime.parse` moves a string with an offset to UTC, and
reads a string without a zone in the zone of the host process. Both give a
wrong local time. A lowercase `z` is accepted. A string that does not parse
keeps the message `expected timestamp (ISO-8601)`. The tests are in
`test/schema_test.dart` (group "the form of a local timestamp").

### 3.2 The host helpers

Four helpers in the sandbox, next to `now()`, `random()` and `log()`, in
`lib/src/host_helpers.dart` (`registerHostHelpers`), registered from
`vm.dart` in both `run` and `compile`. They are pure functions on integers;
the tz database is not involved.

| Helper | Returns |
|---|---|
| `local_time(ts)` | the table `{year, month, day, hour, minute, second, weekday, yday}`; `weekday` is 1 = Monday to 7 = Sunday; `yday` is 1 to 366 |
| `at_clock(ts, "HH:mm")` | the local epoch second of that clock time on the day of `ts` |
| `add_days(ts, n)` | `ts` plus `n` days of 86400 seconds (the same clock time `n` days later, because the numbers are local); `n` may be negative |
| `add_seconds(ts, n)` | `ts + n` |

Arguments and errors:

- `ts` and `n` are integers. A float with no fraction (`3.0`, the result of a
  Lua `/`) counts as an integer. Anything else raises
  `<helper>: argument <i> (<name>) must be an integer`.
- A value whose absolute value is more than 8,640,000,000,000 seconds (the
  range of a Dart `DateTime`), as an argument or as a result of `add_days`
  or `add_seconds`, raises `<helper>: argument <i> (<name>) is out of range`.
- The clock string of `at_clock` is two digits, a colon and two digits,
  00–23 and 00–59. Anything else (`"7:00"`, `"25:00"`, `"07:60"`, a number)
  raises `at_clock: expected "HH:mm"`.

The Dart functions return `value` or `nil, message`. A Lua prelude defines
the four globals and raises the message with `error(message, 2)`, the same
way as the string guards. The engine adds no line number to such an error;
the helper name in the message locates the call. The Dart functions live only
in local upvalues of the prelude.

`now()` returns the epoch second of the `now` argument of `run`. The host
passes the converted (local) value there.

Each helper counts as a host call for the budget, as the three existing
host functions do.

### 3.3 The contracts

| kind | version | zone field |
|---|---|---|
| `scheduling` | 3 | `study.zone` (was `study.timezone`) |
| `question_selection` | 3 | `study.zone` (new; the v2 study group had no zone field) |
| `follow_up` | 3 | `study.zone` (a new `study` group before `settings`) |
| `question_follow_up` | 2 | top-level `zone` after `now` |
| `question_dynamic` | 2 | top-level `zone` after `now` |

`zone` is a non-empty string with the meaning "the IANA zone this run
resolves local times in". The runtime does not check it against the tz
database; the host does with `isValidZone`.

The `follow_up` output: `follow_up` is `{trigger_at, tag}` (a clock time,
local epoch seconds) or `{trigger_in_seconds, tag}` (a duration from `now`
on the time line; an integer, min 1). `trigger_at` and `trigger_in_seconds`
are both optional and nullable in the schema; `tag` stays required. The rule
"exactly one of the two" is in `lib/src/output_rules.dart`
(`checkOutputRules`, `checkFollowUpOutput`), applied by `vm.dart` after the
schema validation of the output: both present or both absent in a non-null
`follow_up` is `outputInvalid` at the path `follow_up` with the message
`exactly one of trigger_at and trigger_in_seconds`. An absent or null
`follow_up` (including the output `{}`) means "no follow-up round".

The doc comment of every `timestamp` field says "local epoch seconds in the
zone of the run". The schema descriptors carry no prose (the
no-`description` rule of the contract fields stays); the prose is in the
server's input reference.

### 3.4 The version

`LuaScriptRuntime.version` and `pubspec.yaml` are `0.13.0`. The tag is
`v0.13.0`. The server and the mobile app pin it.

## 4. The DST rules (server time-model.md §9)

`LocalTimeCodec.toInstant` applies:

- **A gap.** A clock time that does not exist (`02:30` on 2026-03-29 in
  `Europe/Stockholm`) moves forward to the first valid instant, the instant
  of the transition: `01:00Z`, the same instant as `03:00` local. `02:00`
  and `03:00` local on that day give the same instant.
- **An overlap.** A clock time that exists twice (`02:30` on 2026-10-25)
  takes the first occurrence (offset `+02:00`): `00:30Z`.
- **A recurring clock time** keeps its clock time across a DST date. The
  helpers make this automatic: `at_clock(add_days(ts, 1), "07:00")` is
  07:00 on the next day whatever the zone does.
- **A duration** keeps its length. The host resolves `trigger_in_seconds` by
  adding it to the instant of `now`.

The algorithm: read the offsets one day before and one day after the
wall-clock time; the candidates are `wall − offset_before` and
`wall − offset_after`; a candidate is valid when the zone has that offset at
that instant. Both valid → the earlier one (an overlap, or the same instant).
One valid → that one. None valid → a gap: a binary search finds the first
instant with the offset after the transition. It uses only the public
`Location.timeZone(ms)` of `package:timezone`.

## 5. The fixtures

`test/local_time_test.dart`, `test/host_helpers_test.dart` and
`test/follow_up_duration_test.dart` cover, with the zone `Europe/Stockholm`
and the two 2026 changes (2026-03-29 02:00 → 03:00 at 01:00Z; 2026-10-25
03:00 → 02:00 at 01:00Z):

- `toLocal` and `toInstant` round trips on a plain day, on the two DST days,
  on the gap and on the overlap;
- `toLocal` and `toInstant` in `Asia/Tokyo` and `America/New_York` (no DST,
  and a different DST calendar with its own gap and overlap);
- an unknown zone is an `ArgumentError`; `isValidZone`;
- what `TZDateTime` does by itself in a gap and in an overlap (§8);
- `local_time` on the four weekday boundaries, on a leap day, on the last
  day of a leap year and before the epoch;
- `at_clock` on the DST days (the number is local, so no jump), and its
  errors;
- `add_days` across a month end and a year end, with a negative `n`;
- each helper counts as a host call; each helper exists in `compile`;
- a scheduling script that returns `at_clock(add_days(input.now, i), "07:00")`
  for seven days from 2026-10-22, converted with the codec: the instants are
  05:00Z before and 06:00Z from 2026-10-25, all 07:00 on the clock;
- a `follow_up` script that returns `trigger_in_seconds = 1800` at the first
  02:45 local on 2026-10-25 (00:45Z): the host-resolved instant is 01:15Z,
  30 minutes after `now`;
- the `follow_up` output rules: a duration, a clock time, `{}`, nil, both,
  neither, `0`, a fraction, a missing tag.

## 6. What does not change

- `marshal.dart`: a `DateTime` is pushed as its epoch seconds; a Lua number
  is read as epoch seconds into a `DateTime` with `isUtc` true.
- The sandbox seal, the string guards, the budget.
- The validator: `timestamp` accepts an integer, a double or an ISO-8601
  string. Since 0.13.1 the string must end with `Z` (§3.1).
- The `seed` rules.

## 7. Migration of a v2 script

- `trigger_at = input.now + i * 86400` → `trigger_at =
  at_clock(add_days(input.now, i), "07:00")`.
- The hour of a timestamp → `local_time(ts).hour`.
- A follow-up after a duration: `trigger_at = input.now + 1800` →
  `trigger_in_seconds = 1800`.
- `input.study.timezone` → `input.study.zone`.

## 8. Differences from 0.1

- **The example number.** 0.1 said `2026-10-25 07:00` is `1793775600`. That
  number is 2026-11-04 07:00. The correct value is `1792911600`. The
  authority (`nasp_waves_server/docs/design/time-model.md`) has the same
  number and needs the same correction.
- **An acceptance value of the task.** The task said that
  `toLocal(2026-10-25 05:00Z, 'Europe/Stockholm')` is 07:00. The change is at
  01:00Z on that day, so 05:00Z on 2026-10-25 is 06:00 local; 05:00Z is 07:00
  local on 2026-10-24. The tests assert the correct values.
- **The tz variant.** 0.1 left the choice open (`initializeTimeZones` or
  `latest_10y`). The choice is `latest_all` (§3.1).
- **`TZDateTime` by itself.** `tz.TZDateTime(location, 2026, 3, 29, 2, 30)`
  in `Europe/Stockholm` is `01:30Z`: it moves by the length of the gap, not
  to the transition. `tz.TZDateTime(location, 2026, 10, 25, 2, 30)` is
  `01:30Z`: the second occurrence (`+01:00`), not the first. The codec does
  not use this constructor; its own algorithm (§4) gives `01:00Z` and
  `00:30Z`. The tests record both behaviours.
- **The offset type.** In timezone 0.11 `TimeZone.offset` is a `Duration`,
  not an `int` of milliseconds.
- **The file of the output rule.** The "exactly one of" check is in
  `lib/src/output_rules.dart` (0.1 named `host_helpers.dart` as one option).
- **`question_selection` had no zone.** 0.1 said `study.timezone` is renamed
  on `question_selection`; the v2 study group of that kind had no zone
  field, so `study.zone` is a new required field there.
- **The helper errors.** The messages are `<helper>: argument <i> (<name>)
  must be an integer`, `<helper>: argument <i> (<name>) is out of range` and
  `at_clock: expected "HH:mm"`. 0.1 expected the position of the script line
  in the message; the engine adds no line number to `error()`. A float with
  no fraction counts as an integer (0.1 did not say).
- **Formatting.** `lib/` and `test/` were formatted with the current
  `dart format` in a separate commit before the contract changes.
