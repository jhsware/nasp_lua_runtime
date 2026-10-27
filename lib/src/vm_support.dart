// The private helpers of the engine (vm.dart): the sandbox seal and the
// error-message helpers. A part of vm.dart, so that they stay private.
part of 'vm.dart';

/// Strip every ambient capability that is not part of the sanctioned set
/// (§6.2): no `io`/`os`/`package`/`require`/`dofile`/`loadfile`/`load`/
/// `debug`/`print`, and no nondeterministic `math.random`. What remains is
/// base + `math` + `string` + `table` (plus injected `now`/`random`/`log`
/// and the local-time helpers of `host_helpers.dart`).
/// The string functions that would use a Lua pattern are wrapped so that
/// they raise a clear error (`string_guards.dart`).
void _sealSandbox(LuaState ls) {
  const dangerous = <String>[
    'io',
    'os',
    'package',
    'require',
    'dofile',
    'loadfile',
    'load',
    'loadstring',
    'collectgarbage',
    'debug',
    'print',
  ];
  for (final name in dangerous) {
    ls.pushNil();
    ls.setGlobal(name);
  }
  ls.getGlobal('math');
  if (ls.isTable(-1)) {
    ls.pushNil();
    ls.setField(-2, 'random');
    ls.pushNil();
    ls.setField(-2, 'randomseed');
  }
  ls.pop(1);
  installStringGuards(ls);
}

/// Extract a concise message from a Lua/engine error object.
String _luaMessage(Object e) {
  final s = e.toString();
  const prefix = 'Exception: ';
  return _withHints(s.startsWith(prefix) ? s.substring(prefix.length) : s);
}

/// Append a hint to an engine error message that a script author cannot act
/// on without one. `#s` on a string is an error in this engine (the length
/// operator works only on tables); the hint names `s:len()`.
String _withHints(String message) {
  const lengthOfString = 'attempt to get length of a string value';
  if (message.contains(lengthOfString) && !message.contains('s:len()')) {
    return '$message; use s:len() for the length of a string';
  }
  return message;
}
