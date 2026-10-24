import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

/// The local-time helpers of the sandbox (docs/design/time-model.md §3.2,
/// §5). The numbers are local epoch seconds: the epoch seconds of a
/// wall-clock time read as if it were UTC. So no helper sees a DST change.
void main() {
  const runtime = LuaScriptRuntime();

  /// Runs [body] (Lua statements that return one value) in a protected call
  /// inside the entry point. The result is `OK <value>` or `ERR <message>`.
  String run(String body) {
    final source =
        'function dynamic_questions(input) '
        'local ok, v = pcall(function() $body end) '
        'return { reason = (ok and "OK " or "ERR ") .. tostring(v) } end';
    final r = runtime.run(ScriptKind.questionDynamic, source, _input);
    expect(r.ok, isTrue, reason: '${r.error}');
    return r.output!['reason'] as String;
  }

  /// The local epoch second of a wall-clock time.
  int ts(int y, int m, int d, [int h = 0, int mi = 0, int s = 0]) =>
      DateTime.utc(y, m, d, h, mi, s).millisecondsSinceEpoch ~/ 1000;

  String fields(int t) => run(
    'local t = local_time($t) '
    'return t.year .. "-" .. t.month .. "-" .. t.day .. " " .. '
    't.hour .. ":" .. t.minute .. ":" .. t.second .. " w" .. t.weekday .. '
    '" y" .. t.yday',
  );

  group('local_time', () {
    test('2026-10-25 07:00 is 1792911600', () {
      // time-model.md 0.1 gave 1793775600, which is 2026-11-04 07:00.
      expect(ts(2026, 10, 25, 7), 1792911600);
      expect(fields(1792911600), 'OK 2026-10-25 7:0:0 w7 y298');
    });

    test('the four weekday boundaries (1 = Monday, 7 = Sunday)', () {
      // 2026-10-24 is a Saturday, 2026-10-26 a Monday.
      expect(
        fields(ts(2026, 10, 24, 23, 59, 59)),
        'OK 2026-10-24 23:59:59 w6 y297',
      );
      expect(fields(ts(2026, 10, 25)), 'OK 2026-10-25 0:0:0 w7 y298');
      expect(
        fields(ts(2026, 10, 25, 23, 59, 59)),
        'OK 2026-10-25 23:59:59 w7 y298',
      );
      expect(fields(ts(2026, 10, 26)), 'OK 2026-10-26 0:0:0 w1 y299');
    });

    test('a leap day and the last day of a leap year', () {
      expect(fields(ts(2028, 2, 29, 12)), 'OK 2028-2-29 12:0:0 w2 y60');
      expect(fields(ts(2028, 12, 31)), 'OK 2028-12-31 0:0:0 w7 y366');
      expect(fields(ts(2026, 1, 1)), 'OK 2026-1-1 0:0:0 w4 y1');
    });

    test('a negative timestamp', () {
      expect(fields(-1), 'OK 1969-12-31 23:59:59 w3 y365');
    });

    test('a float with no fraction counts as an integer', () {
      expect(run('return local_time(${ts(2026, 10, 25)} / 1).day'), 'OK 25');
    });
  });

  group('at_clock', () {
    test('the DST days keep the clock time (the number is local)', () {
      final day = ts(2026, 10, 25, 12, 34, 56);
      expect(
        run('return at_clock($day, "07:00")'),
        'OK ${ts(2026, 10, 25, 7)}',
      );
      // 02:30 does not exist on 2026-03-29 in Stockholm; as a local number it
      // is a plain value. The host applies the gap rule (LocalTimeCodec).
      expect(
        run('return at_clock(${ts(2026, 3, 29, 9)}, "02:30")'),
        'OK ${ts(2026, 3, 29, 2, 30)}',
      );
    });

    test('00:00 and 23:59', () {
      final day = ts(2026, 6, 1, 15);
      expect(run('return at_clock($day, "00:00")'), 'OK ${ts(2026, 6, 1)}');
      expect(
        run('return at_clock($day, "23:59")'),
        'OK ${ts(2026, 6, 1, 23, 59)}',
      );
    });

    for (final bad in ['7:00', '25:00', '07:60', '0700', '07:00 ', 'aa:bb']) {
      test('"$bad" is an error', () {
        final r = run('return at_clock(0, "$bad")');
        expect(r, startsWith('ERR'));
        expect(r, contains('at_clock: expected "HH:mm"'));
      });
    }

    test('a number as the clock is an error', () {
      expect(
        run('return at_clock(0, 700)'),
        contains('at_clock: expected "HH:mm"'),
      );
    });
  });

  group('add_days and add_seconds', () {
    test('add_days across a month end and a year end', () {
      expect(
        run('return add_days(${ts(2026, 1, 31, 7)}, 1)'),
        'OK ${ts(2026, 2, 1, 7)}',
      );
      expect(
        run('return add_days(${ts(2026, 12, 31, 7)}, 1)'),
        'OK ${ts(2027, 1, 1, 7)}',
      );
    });

    test('add_days with a negative n', () {
      expect(
        run('return add_days(${ts(2027, 1, 1, 7)}, -1)'),
        'OK ${ts(2026, 12, 31, 7)}',
      );
    });

    test('add_days across the DST change keeps the clock time', () {
      expect(
        run('return add_days(${ts(2026, 10, 24, 7)}, 1)'),
        'OK ${ts(2026, 10, 25, 7)}',
      );
    });

    test('add_seconds', () {
      expect(run('return add_seconds(100, 1800)'), 'OK 1900');
      expect(run('return add_seconds(100, -100)'), 'OK 0');
    });

    test('the combination of the design', () {
      final now = ts(2026, 10, 22, 7);
      expect(
        run('return at_clock(add_days($now, 3), "07:00")'),
        'OK ${ts(2026, 10, 25, 7)}',
      );
    });
  });

  group('arguments', () {
    for (final (name, call, message) in [
      (
        'local_time(nil)',
        'local_time(nil)',
        'local_time: argument 1 (ts) must be an integer',
      ),
      (
        'local_time("1")',
        'local_time("1")',
        'local_time: argument 1 (ts) must be an integer',
      ),
      (
        'local_time(1.5)',
        'local_time(1.5)',
        'local_time: argument 1 (ts) must be an integer',
      ),
      (
        'at_clock({}, ...)',
        'at_clock({}, "07:00")',
        'at_clock: argument 1 (ts) must be an integer',
      ),
      (
        'add_days(0, 0.5)',
        'add_days(0, 0.5)',
        'add_days: argument 2 (n) must be an integer',
      ),
      (
        'add_days(0)',
        'add_days(0)',
        'add_days: argument 2 (n) must be an integer',
      ),
      (
        'add_seconds("x", 1)',
        'add_seconds("x", 1)',
        'add_seconds: argument 1 (ts) must be an integer',
      ),
      (
        'local_time(huge)',
        'local_time(9000000000000)',
        'local_time: argument 1 (ts) is out of range',
      ),
    ]) {
      test(name, () {
        final r = run('return $call');
        expect(r, startsWith('ERR'));
        expect(r, contains(message));
      });
    }

    test('the error leaves the script as a runtime error with the message', () {
      const source =
          'function dynamic_questions(input)\n'
          '  local t = at_clock(0, "7:00")\n'
          '  return { reason = tostring(t) }\n'
          'end\n';
      final r = runtime.run(ScriptKind.questionDynamic, source, _input);
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.runtime);
      expect(r.error!.message, contains('at_clock: expected "HH:mm"'));
    });
  });

  group('the sandbox', () {
    test('each helper counts as a host call', () {
      for (final call in [
        'local_time(0)',
        'at_clock(0, "07:00")',
        'add_days(0, 1)',
        'add_seconds(0, 1)',
      ]) {
        final source =
            'function dynamic_questions(input)\n'
            '  local a = $call\n'
            '  local b = $call\n'
            '  return { reason = "x" }\n'
            'end\n';
        final one = runtime.run(
          ScriptKind.questionDynamic,
          source,
          _input,
          budget: const RuntimeBudget(maxHostCalls: 1),
        );
        expect(one.ok, isFalse, reason: call);
        expect(one.error!.type, ScriptErrorType.budgetExceeded, reason: call);
        final two = runtime.run(
          ScriptKind.questionDynamic,
          source,
          _input,
          budget: const RuntimeBudget(maxHostCalls: 2),
        );
        expect(two.ok, isTrue, reason: '$call: ${two.error}');
        expect(two.hostCalls, 2, reason: call);
      }
    });

    test('each helper exists in compile (a top-level call compiles)', () {
      const source =
          'local a = at_clock(0, "07:00")\n'
          'local b = local_time(add_days(add_seconds(a, 1), 1))\n'
          'function dynamic_questions(input) return { reason = "x" } end\n';
      expect(runtime.compile(ScriptKind.questionDynamic, source), isNull);
    });

    test('a top-level helper error fails compile with the message', () {
      const source =
          'local a = at_clock(0, "7:00")\n'
          'function dynamic_questions(input) return { reason = "x" } end\n';
      final e = runtime.compile(ScriptKind.questionDynamic, source);
      expect(e, isNotNull);
      expect(e!.message, contains('at_clock: expected "HH:mm"'));
    });

    test('now() still returns the epoch second of the now argument', () {
      const source =
          'function dynamic_questions(input) '
          'return { reason = tostring(now()) } end';
      final r = runtime.run(
        ScriptKind.questionDynamic,
        source,
        _input,
        now: DateTime.utc(2026, 10, 25, 7),
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.output!['reason'], '1792911600');
    });

    test('no global with the implementation name exists', () {
      expect(run('return tostring(rawget(_G, "__nasp_time_impl"))'), 'OK nil');
    });
  });
}

const Map<String, Object?> _input = {
  'question': {
    'id': 'q',
    'root_question_id': 'r',
    'questions': [
      {
        'id': 'r',
        'role': 'root',
        'type': 'freeText',
        'tags': <String>[],
        'position': 0,
        'dynamic': false,
        'text': 't',
        'options': <Object?>[],
      },
    ],
  },
  'step': {
    'index': 0,
    'question_ids': ['r'],
  },
  'signals': {
    'participant_id': 'p',
    'answers': <Object?>[],
    'earlier_presentations': <Object?>[],
  },
  'now': '2026-03-05T09:00:00.000Z',
  'zone': 'Europe/Stockholm',
  'seed': 1,
};
