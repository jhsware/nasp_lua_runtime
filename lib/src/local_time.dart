/// The local-time codec of the hosts (docs/design/time-model.md §3.1, §4).
///
/// Every `timestamp` of every contract is **local epoch seconds** in the zone
/// of the run: a wall-clock time encoded as the epoch seconds of that
/// wall-clock time read as if it were UTC (`2026-10-25 07:00` is `1792911600`
/// in any zone). The host converts an instant to local time before a run and
/// converts a local time back to an instant after a run. Both hosts use this
/// class, so the conversion is the same on the server and on the phone.
///
/// A local time is a [DateTime] with `isUtc` true whose fields are the
/// wall-clock time. The marshaller pushes it to Lua as its epoch seconds,
/// which are the local epoch seconds.
library;

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Converts between instants and local wall-clock times in an IANA zone.
///
/// The tz database is the full set of `package:timezone`
/// (`data/latest_all.dart`: every canonical zone and every link name, with
/// the full history). It is loaded on the first call.
///
/// The DST rules of [toInstant]:
/// - a gap (a wall-clock time that does not exist) moves forward to the
///   first valid instant, which is the instant of the transition;
/// - an overlap (a wall-clock time that exists twice) takes the first
///   occurrence, which is the earlier instant.
abstract final class LocalTimeCodec {
  static bool _initialised = false;

  static void _ensureInitialised() {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    _initialised = true;
  }

  static tz.Location _location(String zone) {
    _ensureInitialised();
    try {
      return tz.getLocation(zone);
    } on tz.LocationNotFoundException {
      throw ArgumentError('unknown zone: $zone');
    }
  }

  /// True when [id] is a zone of the bundled tz database.
  static bool isValidZone(String id) {
    if (id.isEmpty) return false;
    _ensureInitialised();
    try {
      tz.getLocation(id);
      return true;
    } on tz.LocationNotFoundException {
      return false;
    }
  }

  /// The wall-clock time of [instant] in [zone], as a [DateTime] with `isUtc`
  /// true. Throws [ArgumentError] for an unknown zone.
  static DateTime toLocal(DateTime instant, String zone) {
    final location = _location(zone);
    final utcMillis = instant.toUtc().millisecondsSinceEpoch;
    final offset = location.timeZone(utcMillis).offset.inMilliseconds;
    return DateTime.fromMillisecondsSinceEpoch(utcMillis + offset, isUtc: true);
  }

  /// The instant of the wall-clock time of [local] in [zone]. The fields of
  /// [local] are read as the wall-clock time; its `isUtc` flag is not used.
  /// Throws [ArgumentError] for an unknown zone.
  ///
  /// A gap moves forward to the instant of the transition. An overlap takes
  /// the earlier instant.
  static DateTime toInstant(DateTime local, String zone) {
    final location = _location(zone);
    final wall = DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    ).millisecondsSinceEpoch;

    int offsetAt(int utcMillis) =>
        location.timeZone(utcMillis).offset.inMilliseconds;

    // The offsets one day before and one day after the wall-clock time. A
    // zone has at most one transition in two days, so the instant is
    // `wall - before` or `wall - after`.
    const day = Duration.millisecondsPerDay;
    final before = offsetAt(wall - day);
    final after = offsetAt(wall + day);

    final early = wall - before;
    final late = wall - after;
    final earlyValid = offsetAt(early) == before;
    final lateValid = offsetAt(late) == after;

    if (earlyValid && lateValid) {
      // One instant (no transition near), or an overlap: the earlier one.
      return DateTime.fromMillisecondsSinceEpoch(
        early < late ? early : late,
        isUtc: true,
      );
    }
    if (earlyValid)
      return DateTime.fromMillisecondsSinceEpoch(early, isUtc: true);
    if (lateValid)
      return DateTime.fromMillisecondsSinceEpoch(late, isUtc: true);

    // A gap: no instant has this wall-clock time. The transition lies in
    // (lo, hi]; find the first instant that has the offset after it.
    var lo = late < early ? late : early;
    var hi = late < early ? early : late;
    while (hi - lo > 1) {
      final mid = lo + (hi - lo) ~/ 2;
      if (offsetAt(mid) == after) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(hi, isUtc: true);
  }
}
