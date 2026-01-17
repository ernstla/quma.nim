import std/os

import ./errors
import ./store

type FsScriptStore* = ref object of ScriptStore
  sqlDirs: seq[string]

proc initFsScriptStore*(sqlDirs: openArray[string]): FsScriptStore =
  FsScriptStore(sqlDirs: @sqlDirs)

proc sqlDirs*(store: FsScriptStore): seq[string] =
  store.sqlDirs

proc scriptFilePath(dir: string, id: ScriptId): string =
  joinPath(dir, id & ".sql")

proc templateFilePath(dir: string, id: ScriptId): string =
  joinPath(dir, id & ".msql")

method hasNamespace*(store: FsScriptStore, name: string): bool =
  for dir in store.sqlDirs:
    let p = joinPath(dir, name)
    if dirExists(p):
      return true
  false

method getScript*(store: FsScriptStore, id: ScriptId): Script =
  for dir in store.sqlDirs:
    let sqlPath = scriptFilePath(dir, id)
    if fileExists(sqlPath):
      return Script(id: id, sql: readFile(sqlPath), isTemplate: false, origin: sqlPath)

    let tmplPath = templateFilePath(dir, id)
    if fileExists(tmplPath):
      return Script(id: id, sql: readFile(tmplPath), isTemplate: true, origin: tmplPath)

  raise newException(ScriptNotFoundError, "Script not found: " & id)
