import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

/// The codec cases of docs/design/time-model.md §5. The zone
/// `Europe/Stockholm` changes on 2026-03-29 (02:00 -> 03:00, at 01:00Z) and
/// on 2026-10-25 (03:00 -> 02:00, at 01:00Z).
void main() {
  const stockholm = 'Europe/Stockholm';

  group('LocalTimeCodec.toLocal', () {
    test('a plain day in Europe/Stockholm (+02:00)', () {
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 6, 10, 5), stockholm),
        DateTime.utc(2026, 6, 10, 7),
      );
    });

    test('a winter day in Europe/Stockholm (+01:00)', () {
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 1, 10, 6), stockholm),
        DateTime.utc(2026, 1, 10, 7),
      );
    });

    test('2026-10-25 05:00Z is 06:00 local (after the change)', () {
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 10, 25, 5), stockholm),
        DateTime.utc(2026, 10, 25, 6),
      );
    });

    test('2026-10-24 05:00Z is 07:00 local (before the change)', () {
      // The day before the change the offset is +02:00. On 2026-10-25 the
      // offset is +01:00 from 01:00Z, so 05:00Z on that day is 06:00 local.
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 10, 24, 5), stockholm),
        DateTime.utc(2026, 10, 24, 7),
      );
    });

    test('the two occurrences of 02:30 on 2026-10-25', () {
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 10, 25, 0, 30), stockholm),
        DateTime.utc(2026, 10, 25, 2, 30),
      );
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 10, 25, 1, 30), stockholm),
        DateTime.utc(2026, 10, 25, 2, 30),
      );
    });

    test('around the gap on 2026-03-29', () {
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 3, 29, 0, 59), stockholm),
        DateTime.utc(2026, 3, 29, 1, 59),
      );
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 3, 29, 1), stockholm),
        DateTime.utc(2026, 3, 29, 3),
      );
    });

    test('the result is a UTC DateTime whatever the input flag', () {
      final local = LocalTimeCodec.toLocal(
        DateTime.utc(2026, 6, 10, 5).toLocal(),
        stockholm,
      );
      expect(local.isUtc, isTrue);
      expect(local, DateTime.utc(2026, 6, 10, 7));
    });

    test('Asia/Tokyo has no DST (+09:00 on 2026-10-25)', () {
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 10, 25, 5), 'Asia/Tokyo'),
        DateTime.utc(2026, 10, 25, 14),
      );
    });

    test('America/New_York on its 2026 DST days', () {
      const ny = 'America/New_York';
      // 2026-03-08: 02:00 EST -> 03:00 EDT at 07:00Z.
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 3, 8, 6, 30), ny),
        DateTime.utc(2026, 3, 8, 1, 30),
      );
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 3, 8, 7, 30), ny),
        DateTime.utc(2026, 3, 8, 3, 30),
      );
      // 2026-11-01: 02:00 EDT -> 01:00 EST at 06:00Z.
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 11, 1, 5, 30), ny),
        DateTime.utc(2026, 11, 1, 1, 30),
      );
      expect(
        LocalTimeCodec.toLocal(DateTime.utc(2026, 11, 1, 6, 30), ny),
        DateTime.utc(2026, 11, 1, 1, 30),
      );
    });
  });

  group('LocalTimeCodec.toInstant', () {
    test('the acceptance round trip on 2026-10-25 07:00 local', () {
      // 07:00 local on 2026-10-25 is after the change (+01:00).
      final local = LocalTimeCodec.toLocal(
        DateTime.utc(2026, 10, 25, 6),
        stockholm,
      );
      expect(local, DateTime.utc(2026, 10, 25, 7));
      expect(
        LocalTimeCodec.toInstant(local, stockholm),
        DateTime.utc(2026, 10, 25, 6),
      );
    });

    test('round trips on a plain day and on the two DST days', () {
      for (final instant in [
        DateTime.utc(2026, 6, 10, 5),
        DateTime.utc(2026, 1, 10, 6),
        DateTime.utc(2026, 3, 29, 0, 30),
        DateTime.utc(2026, 3, 29, 1),
        DateTime.utc(2026, 3, 29, 5),
        DateTime.utc(2026, 10, 25, 0, 30),
        DateTime.utc(2026, 10, 25, 5),
        DateTime.utc(2026, 10, 24, 5),
      ]) {
        final local = LocalTimeCodec.toLocal(instant, stockholm);
        expect(
          LocalTimeCodec.toInstant(local, stockholm),
          instant,
          reason: 'round trip of $instant',
        );
      }
    });

    test('the gap: 02:30 on 2026-03-29 moves forward to 01:00Z', () {
      expect(
        LocalTimeCodec.toInstant(DateTime.utc(2026, 3, 29, 2, 30), stockholm),
        DateTime.utc(2026, 3, 29, 1),
      );
      expect(
        LocalTimeCodec.toInstant(DateTime.utc(2026, 3, 29, 2), stockholm),
        DateTime.utc(2026, 3, 29, 1),
      );
      expect(
        LocalTimeCodec.toInstant(DateTime.utc(2026, 3, 29, 3), stockholm),
        DateTime.utc(2026, 3, 29, 1),
      );
    });

    test('the overlap: 02:30 on 2026-10-25 is the first occurrence 00:30Z', () {
      expect(
        LocalTimeCodec.toInstant(DateTime.utc(2026, 10, 25, 2, 30), stockholm),
        DateTime.utc(2026, 10, 25, 0, 30),
      );
    });

    test('the fields are read whatever the isUtc flag of the input', () {
      final wall = DateTime(2026, 6, 10, 7);
      expect(
        LocalTimeCodec.toInstant(wall, stockholm),
        DateTime.utc(2026, 6, 10, 5),
      );
    });

    test('America/New_York gap and overlap', () {
      const ny = 'America/New_York';
      expect(
        LocalTimeCodec.toInstant(DateTime.utc(2026, 3, 8, 2, 30), ny),
        DateTime.utc(2026, 3, 8, 7),
      );
      expect(
        LocalTimeCodec.toInstant(DateTime.utc(2026, 11, 1, 1, 30), ny),
        DateTime.utc(2026, 11, 1, 5, 30),
      );
    });

    test('Asia/Tokyo', () {
      expect(
        LocalTimeCodec.toInstant(DateTime.utc(2026, 10, 25, 7), 'Asia/Tokyo'),
        DateTime.utc(2026, 10, 24, 22),
      );
    });

    test('UTC is the identity', () {
      final t = DateTime.utc(2026, 10, 25, 2, 30);
      expect(LocalTimeCodec.toLocal(t, 'UTC'), t);
      expect(LocalTimeCodec.toInstant(t, 'UTC'), t);
    });
  });

  group('zones', () {
    test('an unknown zone is an ArgumentError', () {
      expect(
        () => LocalTimeCodec.toLocal(DateTime.utc(2026), 'Mars/Olympus'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'unknown zone: Mars/Olympus',
          ),
        ),
      );
      expect(
        () => LocalTimeCodec.toInstant(DateTime.utc(2026), 'Stockholm'),
        throwsArgumentError,
      );
    });

    test('isValidZone', () {
      expect(LocalTimeCodec.isValidZone(stockholm), isTrue);
      expect(LocalTimeCodec.isValidZone('UTC'), isTrue);
      expect(LocalTimeCodec.isValidZone('America/New_York'), isTrue);
      expect(LocalTimeCodec.isValidZone('Mars/Olympus'), isFalse);
      expect(LocalTimeCodec.isValidZone('Stockholm'), isFalse);
      expect(LocalTimeCodec.isValidZone(''), isFalse);
    });
  });

  // What TZDateTime does by itself. The codec does not use this constructor;
  // these cases record the difference that the codec corrects
  // (docs/design/time-model.md "Differences from 0.1").
  group('TZDateTime by itself (recorded, not used)', () {
    setUpAll(() => LocalTimeCodec.isValidZone(stockholm));

    test('in the gap it shifts by the gap length (01:30Z, not 01:00Z)', () {
      final loc = tz.getLocation(stockholm);
      final t = tz.TZDateTime(loc, 2026, 3, 29, 2, 30);
      expect(t.toUtc(), DateTime.utc(2026, 3, 29, 1, 30));
    });

    test('in the overlap it takes the second occurrence (01:30Z)', () {
      final loc = tz.getLocation(stockholm);
      final t = tz.TZDateTime(loc, 2026, 10, 25, 2, 30);
      expect(t.toUtc(), DateTime.utc(2026, 10, 25, 1, 30));
    });
  });
}
