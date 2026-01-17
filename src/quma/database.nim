import std/strutils

import ./errors
import ./store

type Database* = ref object
  uri: string
  store: ScriptStore

proc initDatabase*(uri: string, store: ScriptStore = nil): Database =
  Database(uri: uri, store: store)

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
