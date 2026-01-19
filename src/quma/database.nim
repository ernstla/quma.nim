import std/strutils

import ./backend
import ./errors
import ./store

const sqliteEnabled* = defined(qumaSqlite)
const postgresEnabled* = defined(qumaPostgres)
const mysqlEnabled* = defined(qumaMysql)
const hasEnabledBackends = sqliteEnabled or postgresEnabled or mysqlEnabled

when not hasEnabledBackends:
  {.
    error:
      "No database backend enabled. Compile with -d:qumaSqlite, -d:qumaPostgres, and/or -d:qumaMysql."
  .}

when sqliteEnabled:
  import ./platform/sqlite

when postgresEnabled:
  import ./platform/postgres

when mysqlEnabled:
  import ./platform/mysql

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

  when mysqlEnabled:
    if uri.startsWith("mysql://") or uri.startsWith("mariadb://"):
      return initMysqlBackend()

  # Provide helpful error messages based on what's compiled in
  var msg = "Unsupported database URI: " & uri
  msg.add "\nCompiled backends: "
  var backends: seq[string] = @[]
  when sqliteEnabled:
    backends.add "sqlite"
  when postgresEnabled:
    backends.add "postgres"
  when mysqlEnabled:
    backends.add "mysql"
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
