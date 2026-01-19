import std/strutils

import ./backend
import ./errors
import ./store
import ./platform/sqlite

type Database* = ref object
  uri: string
  store: ScriptStore
  echoSql: bool
  strictTmpl: bool
  dbBackend: DbBackend

proc detectBackend(uri: string): DbBackend =
  ## Detects the appropriate backend based on the URI scheme.
  if uri.startsWith("sqlite://"):
    return initSqliteBackend()

  raise newException(QumaError, "Unsupported database URI scheme: " & uri)

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
