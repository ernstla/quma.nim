import std/strutils

import ./errors
import ./store

type Database* = ref object
  uri: string
  store: ScriptStore
  echoSql: bool
  strictTmpl: bool

proc initDatabase*(
    uri: string, store: ScriptStore = nil, echo = false, strictTemplates = false
): Database =
  Database(uri: uri, store: store, echoSql: echo, strictTmpl: strictTemplates)

proc echo*(db: Database): bool =
  db.echoSql

proc strictTemplates*(db: Database): bool =
  db.strictTmpl

proc uri*(db: Database): string =
  db.uri

proc scriptStore*(db: Database): ScriptStore =
  db.store

proc sqlitePathOrError*(db: Database): string =
  if db.uri == "sqlite:///:memory:":
    return ":memory:"

  if db.uri.startsWith("sqlite:///"):
    return db.uri["sqlite:///".len .. ^1]

  raise newException(QumaError, "Unsupported database uri: " & db.uri)
