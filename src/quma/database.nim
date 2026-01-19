import std/strutils

import ./backend
import ./errors
import ./store

# Compile-time backend selection:
# - If any -d:qumaSqlite or -d:qumaPostgres flag is set, only include those backends
# - If no flags are set, include all backends (default)

const hasExplicitBackends =
  defined(qumaSqlite) or defined(qumaPostgres) or defined(qumaMysql)

# SQLite backend
when not hasExplicitBackends or defined(qumaSqlite):
  import ./platform/sqlite
  const sqliteEnabled* = true
else:
  const sqliteEnabled* = false

# PostgreSQL backend
when not hasExplicitBackends or defined(qumaPostgres):
  import ./platform/postgres
  const postgresEnabled* = true
else:
  const postgresEnabled* = false

type Database* = ref object
  uri: string
  store: ScriptStore
  echoSql: bool
  strictTmpl: bool
  dbBackend: DbBackend

proc detectBackend(uri: string): DbBackend =
  ## Detects the appropriate backend based on the URI scheme.
  when sqliteEnabled:
    if uri.startsWith("sqlite://"):
      return initSqliteBackend()

  when postgresEnabled:
    if uri.startsWith("postgres://"):
      return initPostgresBackend()

  # Provide helpful error messages based on what's compiled in
  var msg = "Unsupported database URI: " & uri
  when hasExplicitBackends:
    msg.add "\nCompiled backends: "
    var backends: seq[string] = @[]
    when sqliteEnabled:
      backends.add "sqlite"
    when postgresEnabled:
      backends.add "postgres"
    msg.add backends.join(", ")
  raise newException(QumaError, msg)

proc initDatabase*(
    uri: string, store: ScriptStore = nil, echo = false, strictTemplates = false
): Database =
  let backend = detectBackend(uri)
  Database(
    uri: uri,
    store: store,
    echoSql: echo,
    strictTmpl: strictTemplates,
    dbBackend: backend,
  )

proc echo*(db: Database): bool =
  db.echoSql

proc strictTemplates*(db: Database): bool =
  db.strictTmpl

proc uri*(db: Database): string =
  db.uri

proc scriptStore*(db: Database): ScriptStore =
  db.store

proc backend*(db: Database): DbBackend =
  db.dbBackend
