/// The local-time helpers of the sandbox (docs/design/time-model.md §3.2).
///
/// Every timestamp a script sees is **local epoch seconds** in the zone of
/// the run (the epoch seconds of the wall-clock time read as if it were
/// UTC). The four helpers are pure functions on those integers; the tz
/// database is not involved:
///
/// - `local_time(ts)` — the table `{year, month, day, hour, minute, second,
///   weekday, yday}`; `weekday` is 1 = Monday to 7 = Sunday, `yday` is 1 to
///   366.
/// - `at_clock(ts, "HH:mm")` — the local epoch second of that clock time on
///   the day of `ts`.
/// - `add_days(ts, n)` — `ts + n * 86400` (the same clock time `n` days
///   later; `n` may be negative).
/// - `add_seconds(ts, n)` — `ts + n`.
///
/// Each helper counts as a host call for the budget. An argument that is not
/// an integer (a number with a fraction, a string, nil, a table) and a clock
/// string that is not `HH:mm` raise a Lua error with one of these messages:
///
/// - `<helper>: argument <i> (<name>) must be an integer`
/// - `<helper>: argument <i> (<name>) is out of range`
/// - `at_clock: expected "HH:mm"`
///
/// A float with no fraction (`3.0`) counts as an integer, because a Lua
/// division (`/`) always gives a float.
///
/// The Dart implementations return `value` or `nil, message`; a Lua prelude
/// wraps them and raises the message with `error(message, 2)`, the way the
/// string guards do (`string_guards.dart`). The engine adds no line number
/// to an error raised with `error()`, so the helper name in the message
/// locates the call. The implementations live only in local upvalues of the
/// prelude; a script cannot reach them.
library;

import 'package:lua_dardo_plus/lua.dart';

/// The temporary global that holds the Dart implementations while the
/// prelude runs. It is set to nil again before any script loads.
const String _implName = '__nasp_time_impl';

/// The names of the four helpers, in the order of the design.
const List<String> hostHelperNames = [
  'local_time',
  'at_clock',
  'add_days',
  'add_seconds',
];

/// The largest absolute timestamp (seconds) a helper accepts: the range of a
/// Dart [DateTime] (±100,000,000 days from the epoch).
const int _maxSeconds = 8640000000000;

const String _hostHelperPrelude =
    '''
local impl = $_implName
local error = error
local lt, ac, ad, as =
  impl.local_time, impl.at_clock, impl.add_days, impl.add_seconds

local_time = function(...)
  local r, e = lt(...)
  if e then error(e, 2) end
  return r
end

at_clock = function(...)
  local r, e = ac(...)
  if e then error(e, 2) end
  return r
end

add_days = function(...)
  local r, e = ad(...)
  if e then error(e, 2) end
  return r
end

add_seconds = function(...)
  local r, e = as(...)
  if e then error(e, 2) end
  return r
end
''';

/// Register the four helpers as globals of [ls]. Call it after the sandbox
/// is sealed. [onHostCall] runs first in each helper call (the host-call
/// count and the budget check of the runtime); it may throw to abort the
/// run.
void registerHostHelpers(LuaState ls, {required void Function() onHostCall}) {
  ls.newTable();
  final table = ls.getTop();

  void add(String name, int Function(LuaState s) body) {
    ls.pushDartFunction((s) {
      onHostCall();
      return body(s);
    });
    ls.setField(table, name);
  }

  add('local_time', (s) {
    final ts = _integerArg(s, 1, 'local_time', 'ts');
    if (ts == null) return 2;
    final t = _dateOf(ts);
    s.newTable();
    final out = s.getTop();
    void field(String key, int value) {
      s.pushInteger(value);
      s.setField(out, key);
    }

    field('year', t.year);
    field('month', t.month);
    field('day', t.day);
    field('hour', t.hour);
    field('minute', t.minute);
    field('second', t.second);
    field('weekday', t.weekday);
    field('yday', _yearDay(t));
    return 1;
  });

  add('at_clock', (s) {
    final ts = _integerArg(s, 1, 'at_clock', 'ts');
    if (ts == null) return 2;
    final clock = _parseClock(s);
    if (clock == null) {
      return _fail(s, 'at_clock: expected "HH:mm"');
    }
    final day = _dateOf(ts);
    final result = DateTime.utc(
      day.year,
      day.month,
      day.day,
      clock.$1,
      clock.$2,
    );
    s.pushInteger(result.millisecondsSinceEpoch ~/ 1000);
    return 1;
  });

  add('add_days', (s) {
    final ts = _integerArg(s, 1, 'add_days', 'ts');
    if (ts == null) return 2;
    final n = _integerArg(s, 2, 'add_days', 'n');
    if (n == null) return 2;
    final result = ts + n * Duration.secondsPerDay;
    if (result.abs() > _maxSeconds) {
      return _fail(s, 'add_days: argument 2 (n) is out of range');
    }
    s.pushInteger(result);
    return 1;
  });

  add('add_seconds', (s) {
    final ts = _integerArg(s, 1, 'add_seconds', 'ts');
    if (ts == null) return 2;
    final n = _integerArg(s, 2, 'add_seconds', 'n');
    if (n == null) return 2;
    final result = ts + n;
    if (result.abs() > _maxSeconds) {
      return _fail(s, 'add_seconds: argument 2 (n) is out of range');
    }
    s.pushInteger(result);
    return 1;
  });

  ls.setGlobal(_implName);
  try {
    final ThreadStatus loaded;
    try {
      loaded = ls.loadString(_hostHelperPrelude);
    } catch (e) {
      throw StateError('host helper prelude does not compile: $e');
    }
    if (loaded != ThreadStatus.luaOk) {
      throw StateError('host helper prelude does not compile: ${ls.toStr(-1)}');
    }
    final ThreadStatus ran;
    try {
      ran = ls.pCall(0, 0, 0);
    } catch (e) {
      throw StateError('host helper prelude failed: $e');
    }
    if (ran != ThreadStatus.luaOk) {
      throw StateError('host helper prelude failed: ${ls.toStr(-1)}');
    }
  } finally {
    ls.pushNil();
    ls.setGlobal(_implName);
  }
}

/// Push `nil, message` and return the result count 2.
int _fail(LuaState s, String message) {
  s.pushNil();
  s.pushString(message);
  return 2;
}

/// Read argument [index] as an integer. On failure push `nil, message` and
/// return null (the caller returns 2).
int? _integerArg(LuaState s, int index, String helper, String name) {
  int? value;
  if (s.isInteger(index)) {
    value = s.toInteger(index);
  } else if (s.type(index) == LuaType.luaNumber) {
    final d = s.toNumber(index);
    if (d.isFinite && d == d.truncateToDouble()) value = d.toInt();
  }
  if (value == null) {
    _fail(s, '$helper: argument $index ($name) must be an integer');
    return null;
  }
  if (value.abs() > _maxSeconds) {
    _fail(s, '$helper: argument $index ($name) is out of range');
    return null;
  }
  return value;
}

/// Parse argument 2 as `HH:mm` (two digits, a colon, two digits; 00–23 and
/// 00–59). Null when it is not a string of that form.
(int, int)? _parseClock(LuaState s) {
  if (s.type(2) != LuaType.luaString) return null;
  final text = s.toStr(2);
  if (text == null || text.length != 5 || text[2] != ':') return null;
  final hour = _twoDigits(text.substring(0, 2));
  final minute = _twoDigits(text.substring(3, 5));
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return (hour, minute);
}

int? _twoDigits(String text) {
  const zero = 48; // '0'
  var value = 0;
  for (final unit in text.codeUnits) {
    final digit = unit - zero;
    if (digit < 0 || digit > 9) return null;
    value = value * 10 + digit;
  }
  return value;
}

DateTime _dateOf(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

int _yearDay(DateTime t) =>
    DateTime.utc(
      t.year,
      t.month,
      t.day,
    ).difference(DateTime.utc(t.year)).inDays +
    1;
