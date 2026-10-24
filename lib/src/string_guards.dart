/// The string guards of the sandbox (README "String functions").
///
/// The Lua engine (`lua_dardo_plus`) does not support the Lua patterns. In
/// runtime 0.11.0 a pattern call such as `s:find("%d")` or
/// `s:match("(%a+)")` gave a wrong result (no match) with no error, and
/// `gmatch`, `gsub` with a function and `reverse` gave an unclear engine
/// error. Since 0.12.0 a string function that would use a pattern raises a
/// clear Lua error instead:
///
/// `string.<name>: Lua patterns are not supported; use <hint>`
///
/// The rule. A text is a *pattern* when it contains one of the special
/// characters `^ $ * + ? . ( ) [ ] % -`.
/// - `string.find(s, p, init, plain)`: allowed when `plain` is true, or when
///   `p` is not a pattern.
/// - `string.match(s, p, init)`: allowed when `p` is not a pattern.
/// - `string.gmatch`: always an error.
/// - `string.gsub(s, p, repl, n)`: allowed when `p` is not a pattern and
///   `repl` is a string (or a number) without `%`.
/// - `string.reverse`: always an error (the engine implementation is broken).
///
/// The guards wrap the original functions in a Lua prelude, so an allowed
/// call keeps the exact behaviour of the engine. The method syntax
/// (`s:find(...)`) reads the same `string` table through the string
/// metatable, so one change covers both call forms. The originals live only
/// in local upvalues of the prelude; a script cannot reach them.
library;

import 'package:lua_dardo_plus/lua.dart';

/// The temporary global that holds the Dart predicate while the prelude runs.
/// It is set to nil again before any script loads.
const String _predicateName = '__nasp_is_pattern';

/// The special characters of a Lua pattern.
const String _specialCharacters = r'^$*+?.()[]%-';

/// True when [text] contains a special character of a Lua pattern.
bool isLuaPattern(String text) {
  for (var i = 0; i < text.length; i++) {
    if (_specialCharacters.contains(text[i])) return true;
  }
  return false;
}

/// The Lua prelude that installs the guards. It must use no pattern itself:
/// the only `find` it calls is a plain find for the `%` character.
const String stringGuardPrelude =
    '''
local string = string
local is_pattern = $_predicateName
local find, match, gsub = string.find, string.match, string.gsub
local type, error, tostring = type, error, tostring

local NOT_SUPPORTED = ": Lua patterns are not supported; use "
local PLAIN_FIND = "s:find(text, init, true)"
local LOOP = "a loop with s:find(text, init, true) and s:sub(i, j)"

string.find = function(s, p, ...)
  local init, plain = ...
  if not plain and is_pattern(p) then
    error("string.find" .. NOT_SUPPORTED .. PLAIN_FIND, 2)
  end
  return find(s, p, ...)
end

string.match = function(s, p, ...)
  if is_pattern(p) then
    error("string.match" .. NOT_SUPPORTED .. PLAIN_FIND, 2)
  end
  return match(s, p, ...)
end

string.gmatch = function()
  error("string.gmatch" .. NOT_SUPPORTED .. LOOP, 2)
end

string.gsub = function(s, p, repl, ...)
  if is_pattern(p) then
    error("string.gsub" .. NOT_SUPPORTED .. LOOP, 2)
  end
  if type(repl) == "number" then repl = tostring(repl) end
  if type(repl) ~= "string" then
    error("string.gsub" .. NOT_SUPPORTED .. LOOP, 2)
  end
  if find(repl, "%", 1, true) then
    error("string.gsub" .. NOT_SUPPORTED .. "a replacement without %", 2)
  end
  return gsub(s, p, repl, ...)
end

string.reverse = function()
  error("string.reverse" .. NOT_SUPPORTED .. "a loop with s:sub(i, i)", 2)
end
''';

/// Install the string guards in [ls]. Call it after `openLibs` and before
/// any script loads. A failure of the prelude is a bug of the runtime and
/// throws a [StateError].
void installStringGuards(LuaState ls) {
  ls.pushDartFunction((s) {
    final text = s.isString(1) ? s.toStr(1) : null;
    s.pushBoolean(text != null && isLuaPattern(text));
    return 1;
  });
  ls.setGlobal(_predicateName);
  try {
    final ThreadStatus loaded;
    try {
      loaded = ls.loadString(stringGuardPrelude);
    } catch (e) {
      throw StateError('string guard prelude does not compile: $e');
    }
    if (loaded != ThreadStatus.luaOk) {
      throw StateError(
        'string guard prelude does not compile: ${ls.toStr(-1)}',
      );
    }
    final ThreadStatus ran;
    try {
      ran = ls.pCall(0, 0, 0);
    } catch (e) {
      throw StateError('string guard prelude failed: $e');
    }
    if (ran != ThreadStatus.luaOk) {
      throw StateError('string guard prelude failed: ${ls.toStr(-1)}');
    }
  } finally {
    ls.pushNil();
    ls.setGlobal(_predicateName);
  }
}
