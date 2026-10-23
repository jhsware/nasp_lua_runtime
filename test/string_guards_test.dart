import 'package:nasp_lua_runtime/nasp_lua_runtime.dart';
import 'package:test/test.dart';

/// The string rule of the runtime (README "String functions").
///
/// The Lua engine (`lua_dardo_plus`) does not support the Lua patterns. In
/// 0.11.0 some pattern calls gave a wrong result with no error. Since 0.12.0 a
/// string function that would use a pattern raises a clear Lua error:
/// `string.<name>: Lua patterns are not supported; use <hint>`. The allowed
/// calls keep the exact 0.11.0 behaviour.
void main() {
  const runtime = LuaScriptRuntime();

  /// Runs [body] (Lua statements that return one value) in a protected call
  /// inside the entry point. The result is `OK <value>` or `ERR <message>`.
  String run(String body) {
    final source = 'function dynamic_questions(input) '
        'local ok, v = pcall(function() $body end) '
        'return { reason = (ok and "OK " or "ERR ") .. tostring(v) } end';
    final r = runtime.run(ScriptKind.questionDynamic, source, _input);
    expect(r.ok, isTrue, reason: '${r.error}');
    return r.output!['reason'] as String;
  }

  const notSupported = 'Lua patterns are not supported';

  group('allowed (same result as 0.11.0)', () {
    for (final (name, body, result) in [
      ('string.len', 'return string.len("abc")', 'OK 3'),
      ('s:len()', 'return ("abc"):len()', 'OK 3'),
      ('# of a table', 'return #{1, 2, 3}', 'OK 3'),
      ('sub', 'return ("abcdef"):sub(2, 4) .. ("abcdef"):sub(-2)', 'OK bcdef'),
      ('upper and lower', 'return ("aB"):upper() .. ("aB"):lower()', 'OK ABab'),
      ('rep', 'return ("ab"):rep(3)', 'OK ababab'),
      ('byte and char', 'return ("A"):byte() .. string.char(66)', 'OK 65B'),
      ('format %s %d %%', 'return string.format("%s=%d%%", "n", 4)', 'OK n=4%'),
      ('format %.1f', 'return string.format("%.1f", 2.25)', 'OK 2.3'),
      ('find, plain', 'return ("a.b"):find(".", 1, true)', 'OK 2'),
      ('find, plain, both positions',
          'local a, b = ("a.b"):find(".", 1, true) return a .. "," .. b',
          'OK 2,2'),
      ('find, plain, init', 'return ("a,b,c"):find(",", 3, true)', 'OK 4'),
      ('find, plain, no match', 'return ("abc"):find("x", 1, true)', 'OK nil'),
      ('find, no special character', 'return ("abc"):find("bc")', 'OK 2'),
      ('string.find, no special character',
          'return string.find("abc", "bc")', 'OK 2'),
      ('match, no special character', 'return ("abc"):match("bc")', 'OK bc'),
      ('match, no match', 'return ("abc"):match("x")', 'OK nil'),
      ('gsub, no special character, with the count',
          'local s, n = ("a-b"):gsub("b", "c") return s .. "," .. n',
          'OK a-c,1'),
      ('gsub, limit', 'return (("aaa"):gsub("a", "b", 2))', 'OK bba'),
      (
        'split with a plain find',
        'local out, i = {}, 1 local s = "a,b,c" while true do '
            'local a, b = s:find(",", i, true) '
            'if a == nil then out[#out + 1] = s:sub(i) break end '
            'out[#out + 1] = s:sub(i, a - 1) i = b + 1 end '
            'return table.concat(out, "|")',
        'OK a|b|c',
      ),
    ]) {
      test(name, () => expect(run(body), result));
    }
  });

  group('forbidden (a clear error)', () {
    for (final (name, body, function) in [
      ('s:find with %d', 'return ("ab12"):find("%d")', 'string.find'),
      ('string.find with %d', 'return string.find("ab12", "%d")',
          'string.find'),
      ('find with .', 'return ("a.b"):find(".")', 'string.find'),
      ('find with . and plain false', 'return ("a.b"):find(".", 1, false)',
          'string.find'),
      ('find with [0-9]', 'return ("ab12"):find("[0-9]")', 'string.find'),
      ('find with ^a', 'return ("abc"):find("^a")', 'string.find'),
      ('find with %.', 'return ("a.b"):find("%.")', 'string.find'),
      ('s:match with a capture', 'return ("k=v"):match("(%a+)=(%a+)")',
          'string.match'),
      ('string.match with a capture',
          'return string.match("k=v", "(%a+)=(%a+)")', 'string.match'),
      ('match with %d+', 'return ("ab12"):match("%d+")', 'string.match'),
      (
        'gmatch',
        'local o = "" for w in ("ab cd"):gmatch("[a-z]+") do o = o .. w end '
            'return o',
        'string.gmatch',
      ),
      ('gmatch with a plain text', 'return ("ab"):gmatch("a")',
          'string.gmatch'),
      ('gsub with a pattern', 'return (("ab12"):gsub("%d", "x"))',
          'string.gsub'),
      ('gsub with a function',
          'return (("ab"):gsub("a", function(m) return "x" end))',
          'string.gsub'),
      ('gsub with a table', 'return (("ab"):gsub("a", { a = "x" }))',
          'string.gsub'),
      ('gsub with % in the replacement',
          'return (("ab"):gsub("a", "%1"))', 'string.gsub'),
      ('gsub with a capture', 'return (("ab"):gsub("(a)", "x"))',
          'string.gsub'),
      ('reverse', 'return ("abc"):reverse()', 'string.reverse'),
      ('string.reverse', 'return string.reverse("abc")', 'string.reverse'),
    ]) {
      test(name, () {
        final result = run(body);
        expect(result, startsWith('ERR'));
        expect(result, contains(function));
        expect(result, contains(notSupported));
      });
    }

    test('the message names the replacement', () {
      expect(run('return ("ab12"):find("%d")'),
          contains('use s:find(text, init, true)'));
      expect(run('return ("abc"):reverse()'), contains('use '));
    });

    test('the script error has the message form of the guard', () {
      // The engine adds no line number to an error raised with `error()` (at
      // any level it gives `[unknown]`), so the function name in the message
      // is what locates the call. Probed on 2026-10-23 with lua_dardo_plus
      // 0.3.x: only VM-internal errors (`nil + 1`, `#s`) carry a line.
      const source = 'function dynamic_questions(input)\n'
          '  local s = "ab12"\n'
          '  local n = s:find("%d")\n'
          '  return { reason = tostring(n) }\n'
          'end\n';
      final r = runtime.run(ScriptKind.questionDynamic, source, _input);
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.runtime);
      expect(
          r.error!.message,
          contains('string.find: Lua patterns are not supported; '
              'use s:find(text, init, true)'));
    });

    test('a forbidden call in the top-level chunk fails compile', () {
      const source = 'local n = ("ab12"):find("%d")\n'
          'function dynamic_questions(input) return { reason = "x" } end\n';
      final e = runtime.compile(ScriptKind.questionDynamic, source);
      expect(e, isNotNull);
      expect(e!.type, ScriptErrorType.runtime);
      expect(e.message, contains(notSupported));
    });

    test('# of a string gives the hint s:len() in the script error', () {
      // The hint is added when the error leaves Lua (the normal case). Inside
      // a Lua pcall the message is the engine's own message.
      const source = 'function dynamic_questions(input)\n'
          '  local n = #"abc"\n'
          '  return { reason = tostring(n) }\n'
          'end\n';
      final r = runtime.run(ScriptKind.questionDynamic, source, _input);
      expect(r.ok, isFalse);
      expect(r.error!.type, ScriptErrorType.runtime);
      expect(r.error!.message, contains('attempt to get length'));
      expect(r.error!.message, contains('use s:len()'));
      expect(run('return #"abc"'), startsWith('ERR'));
    });
  });

  group('unreachable (no original function)', () {
    test('the guarded functions exist', () {
      expect(
          run('return tostring(string.find ~= nil and string.match ~= nil '
              'and string.gmatch ~= nil and string.gsub ~= nil '
              'and string.reverse ~= nil)'),
          'OK true');
    });

    test('no global with the predicate name exists', () {
      expect(run('return tostring(rawget(_G, "__nasp_is_pattern"))'),
          'OK nil');
    });

    test('the method syntax reads the guarded string table', () {
      expect(run('return tostring(getmetatable("").__index == string)'),
          'OK true');
      expect(
          run('return tostring(getmetatable("").__index.find == string.find)'),
          'OK true');
    });

    test('no field of string or of the string metatable is an original', () {
      // Every function reachable from `string` or from the metatable is a
      // guard or an untouched standard function; none has a name that marks
      // a saved original.
      expect(
          run('local bad = 0 '
              'for k in pairs(string) do '
              'if type(k) ~= "string" or k:find("nasp", 1, true) '
              'or k:find("orig", 1, true) or k:find("_", 1, true) == 1 '
              'then bad = bad + 1 end end '
              'for k in pairs(getmetatable("")) do '
              'if k ~= "__index" then bad = bad + 1 end end '
              'return bad'),
          'OK 0');
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
  'seed': 1,
};
