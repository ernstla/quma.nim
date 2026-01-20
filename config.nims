import std/[strutils, os]

proc addUnique(values: var seq[string], value: string) =
  if value notin values:
    values.add value

proc parseBackendArgs(): seq[string] =
  let args = commandLineParams()
  if args.len == 0:
    return @[]
  var selected: seq[string] = @[]
  for arg in args:
    let raw = arg.strip()
    if raw.len == 0 or raw == "--" or raw == "test":
      continue
    if raw.startsWith("-"):
      continue
    let value = raw.toLowerAscii()
    case value
    of "sqlite":
      addUnique(selected, "sqlite")
    of "postgres", "postgresql", "pg":
      addUnique(selected, "postgres")
    of "mysql", "mariadb":
      addUnique(selected, "mysql")
    of "all":
      return @["sqlite", "postgres", "mysql"]
    else:
      quit(
        "Unknown backend argument: " & arg & ". Use sqlite, postgres, mysql, or all."
      )
  selected

proc compileBackends(): seq[string] =
  var selected: seq[string] = @[]
  when defined(qumaSqlite):
    selected.add "sqlite"
  when defined(qumaPostgres):
    selected.add "postgres"
  when defined(qumaMysql):
    selected.add "mysql"
  selected

proc selectedBackends(): seq[string] =
  let args = parseBackendArgs()
  if args.len > 0:
    return args
  compileBackends()

proc flagsForBackends(backends: seq[string]): string =
  var flags: seq[string] = @[]
  for backend in backends:
    case backend
    of "sqlite":
      flags.add "-d:qumaSqlite"
    of "postgres":
      flags.add "-d:qumaPostgres"
    of "mysql":
      flags.add "-d:qumaMysql"
    else:
      discard
  if flags.len == 0:
    return ""
  " " & flags.join(" ")

proc runTests(flags: string) =
  let tests = staticExec("ls tests/test*.nim").strip
  if tests.len == 0:
    quit("No tests found.")

  for testFile in tests.splitWhitespace:
    exec "nim r" & flags & " " & testFile

task test, "Run all unit tests":
  var backends = selectedBackends()
  if backends.len == 0:
    addUnique(backends, "sqlite")
  if "sqlite" notin backends:
    addUnique(backends, "sqlite")
  runTests(flagsForBackends(backends))
