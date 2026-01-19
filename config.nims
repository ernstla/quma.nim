import std/strutils

proc testFlags(): string =
  var flags: seq[string] = @[]
  when defined(qumaPostgres):
    flags.add "-d:qumaPostgres"
  when defined(qumaMysql):
    flags.add "-d:qumaMysql"
  when defined(qumaSqlite):
    flags.add "-d:qumaSqlite"
  if flags.len == 0:
    return " -d:qumaSqlite"
  " " & flags.join(" ")

proc runTests(flags: string) =
  let tests = staticExec("ls tests/t*.nim").strip
  if tests.len == 0:
    quit("No tests found.")

  for testFile in tests.splitWhitespace:
    exec "nim r" & flags & " " & testFile

task test, "Run all unit tests":
  runTests(testFlags())

task testall, "Run all unit tests with all backends":
  runTests(" -d:qumaSqlite -d:qumaPostgres -d:qumaMysql")
