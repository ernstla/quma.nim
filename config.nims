import std/strutils

task test, "Run all unit tests":
  let tests = staticExec("ls tests/t*.nim").strip
  if tests.len == 0:
    quit("No tests found.")

  for testFile in tests.splitWhitespace:
    exec "nim r " & testFile
