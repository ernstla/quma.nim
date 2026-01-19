import std/[os, tables]

import ./errors
import ./params
import ./store
import ./tmplLexer

type FsScriptStore* = ref object of ScriptStore
  sqlDirs: seq[string]
  cacheEnabled: bool
  reloadEnabled: bool
  cache: Table[ScriptId, Script]

proc initFsScriptStore*(
    sqlDirs: openArray[string], cache = true, reload = false
): FsScriptStore =
  FsScriptStore(
    sqlDirs: @sqlDirs,
    cacheEnabled: cache,
    reloadEnabled: reload,
    cache: initTable[ScriptId, Script](),
  )

proc sqlDirs*(store: FsScriptStore): seq[string] =
  store.sqlDirs

proc cacheEnabled*(store: FsScriptStore): bool =
  store.cacheEnabled

proc reloadEnabled*(store: FsScriptStore): bool =
  store.reloadEnabled

proc clearCache*(store: FsScriptStore) =
  if store.cache.len > 0:
    store.cache.clear()

proc scriptFilePath(dir: string, id: ScriptId): string =
  joinPath(dir, id & ".sql")

proc templateFilePath(dir: string, id: ScriptId): string =
  joinPath(dir, id & ".nsql")

method hasNamespace*(store: FsScriptStore, name: string): bool =
  for dir in store.sqlDirs:
    let p = joinPath(dir, name)
    if dirExists(p):
      return true
  false

method getScript*(store: FsScriptStore, id: ScriptId): Script =
  if store.cacheEnabled and not store.reloadEnabled and store.cache.hasKey(id):
    return store.cache[id]

  for dir in store.sqlDirs:
    let sqlPath = scriptFilePath(dir, id)
    if fileExists(sqlPath):
      let sqlText = readFile(sqlPath)
      # Auto-detect template content in .sql files
      let isTemplate = hasTemplateContent(sqlText)
      let script = Script(
        id: id,
        sql: sqlText,
        isTemplate: isTemplate,
        origin: sqlPath,
        compiled: compileNamedSql(sqlText),
      )
      if store.cacheEnabled:
        store.cache[id] = script
      return script

    let tmplPath = templateFilePath(dir, id)
    if fileExists(tmplPath):
      let sqlText = readFile(tmplPath)
      let script = Script(
        id: id,
        sql: sqlText,
        isTemplate: true, # .nsql is always a template
        origin: tmplPath,
        compiled: compileNamedSql(sqlText),
      )
      if store.cacheEnabled:
        store.cache[id] = script
      return script

  raise newException(ScriptNotFoundError, "Script not found: " & id)

proc resolveInclude*(store: FsScriptStore, path: string, currentDir: string): string =
  ## Resolve an include file path and return its content.
  ## Resolution order:
  ## 1. Relative to currentDir (current script's directory)
  ## 2. SQL roots in order (first match wins, so last-added root should be first in sqlDirs)
  ##
  ## If path has no extension, tries: .inc.nsql, .inc.sql, .nsql, .sql
  let extensions =
    if '.' in path:
      @[""] # path already has extension
    else:
      @[".inc.nsql", ".inc.sql", ".nsql", ".sql"]

  # Try relative to current directory first
  for ext in extensions:
    let candidate = normalizedPath(joinPath(currentDir, path & ext))
    if fileExists(candidate):
      return readFile(candidate)

  # Try SQL roots (in order - first one wins)
  for dir in store.sqlDirs:
    for ext in extensions:
      let candidate = normalizedPath(joinPath(dir, path & ext))
      if fileExists(candidate):
        return readFile(candidate)

  raise newException(
    ScriptNotFoundError,
    "Include file not found: " & path & " (from " & currentDir & ")",
  )
