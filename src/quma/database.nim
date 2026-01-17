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
