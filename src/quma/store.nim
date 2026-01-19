import std/[algorithm, os, strutils, tables, sets]
import std/macros

import ./errors
import ./params
import ./tmplLexer

type
  ScriptId* = string

  Script* = object
    id*: ScriptId
    sql*: string
    isTemplate*: bool
    origin*: string
    compiled*: CompiledNamedSql

  ScriptStore* = ref object of RootObj

  EmbeddedScriptStore* = ref object of ScriptStore
    scripts: Table[ScriptId, Script]
    includes: Table[string, string] # path -> content for include files
    baseDir: string # base directory for relative path resolution
    namespaces: HashSet[string]

  OverlayScriptStore* = ref object of ScriptStore
    primary: ScriptStore
    fallback: ScriptStore

proc isIncludeFile*(name: string): bool =
  ## Check if a filename is an include file (.inc.sql or .inc.nsql)
  name.endsWith(".inc.sql") or name.endsWith(".inc.nsql") or name.endsWith(".inc")

proc makeScriptId*(segments: openArray[string]): ScriptId =
  segments.join("/")

proc addNamespaces(store: EmbeddedScriptStore, id: ScriptId) =
  let parts = id.split("/")
  if parts.len <= 1:
    return
  var current = parts[0]
  store.namespaces.incl(current)
  for idx in 1 ..< parts.len - 1:
    current &= "/" & parts[idx]
    store.namespaces.incl(current)

proc initEmbeddedScriptStore*(
    entries: openArray[Script],
    includes: openArray[(string, string)] = [],
    baseDir: string = "",
): EmbeddedScriptStore =
  result = EmbeddedScriptStore(
    scripts: initTable[ScriptId, Script](),
    includes: initTable[string, string](),
    baseDir: baseDir,
    namespaces: initHashSet[string](),
  )
  for entry in entries:
    result.scripts[entry.id] = entry
    result.addNamespaces(entry.id)
  for (path, content) in includes:
    result.includes[path] = content

proc initOverlayScriptStore*(
    primary: ScriptStore, fallback: ScriptStore
): OverlayScriptStore =
  OverlayScriptStore(primary: primary, fallback: fallback)

method hasNamespace*(store: ScriptStore, name: string): bool {.base.} =
  false

method getScript*(store: ScriptStore, id: ScriptId): Script {.base.} =
  raise newException(QumaError, "ScriptStore.getScript not implemented")

method resolveInclude*(
    store: ScriptStore, path: string, currentDir: string
): string {.base.} =
  ## Resolve an include file and return its content.
  ## path: the include path from {#include "path"}
  ## currentDir: directory of the script containing the include
  raise newException(QumaError, "ScriptStore.resolveInclude not implemented")

method hasNamespace*(store: EmbeddedScriptStore, name: string): bool =
  store.namespaces.contains(name)

method getScript*(store: EmbeddedScriptStore, id: ScriptId): Script =
  if store.scripts.hasKey(id):
    return store.scripts[id]
  raise newException(ScriptNotFoundError, "Script not found: " & id)

method resolveInclude*(
    store: EmbeddedScriptStore, path: string, currentDir: string
): string =
  ## Resolve include from embedded store.
  ## Tries path directly, then with extensions.
  let extensions =
    if '.' in path:
      @[""]
    else:
      @[".inc.nsql", ".inc.sql", ".nsql", ".sql"]

  # Try relative to currentDir first (normalize to relative path from baseDir)
  if currentDir.len > 0 and store.baseDir.len > 0:
    for ext in extensions:
      let relPath = normalizedPath(joinPath(currentDir, path & ext))
      # Convert to path relative to baseDir for lookup
      if store.includes.hasKey(relPath):
        return store.includes[relPath]

  # Try from baseDir
  for ext in extensions:
    let candidate = normalizedPath(joinPath(store.baseDir, path & ext))
    if store.includes.hasKey(candidate):
      return store.includes[candidate]

  # Try path directly (for absolute paths stored in includes)
  for ext in extensions:
    let candidate = path & ext
    if store.includes.hasKey(candidate):
      return store.includes[candidate]

  raise newException(
    ScriptNotFoundError,
    "Include file not found: " & path & " (from " & currentDir & ")",
  )

method hasNamespace*(store: OverlayScriptStore, name: string): bool =
  let primaryHas = store.primary != nil and store.primary.hasNamespace(name)
  let fallbackHas = store.fallback != nil and store.fallback.hasNamespace(name)
  primaryHas or fallbackHas

method getScript*(store: OverlayScriptStore, id: ScriptId): Script =
  if store.primary != nil:
    try:
      return store.primary.getScript(id)
    except ScriptNotFoundError:
      discard
  if store.fallback != nil:
    return store.fallback.getScript(id)
  raise newException(ScriptNotFoundError, "Script not found: " & id)

method resolveInclude*(
    store: OverlayScriptStore, path: string, currentDir: string
): string =
  ## Resolve include from overlay store - tries primary first, then fallback.
  if store.primary != nil:
    try:
      return store.primary.resolveInclude(path, currentDir)
    except ScriptNotFoundError:
      discard
  if store.fallback != nil:
    return store.fallback.resolveInclude(path, currentDir)
  raise newException(
    ScriptNotFoundError,
    "Include file not found: " & path & " (from " & currentDir & ")",
  )

macro embedSqlDir*(dir: static[string]): untyped =
  let projectDir = getProjectPath()
  let baseDir =
    if dir.isAbsolute:
      dir
    else:
      let callsite = instantiationInfo(fullPaths = true)
      let callDir = splitFile(callsite.filename).dir
      if callDir.len > 0:
        if callDir.isAbsolute:
          joinPath(callDir, dir)
        else:
          joinPath(projectDir, callDir, dir)
      else:
        joinPath(projectDir, dir)
  var normalized = baseDir
  normalizePath(normalized)
  if not dirExists(normalized):
    error("embedSqlDir path not found: " & normalized)

  # Collect scripts and include files separately
  var selected = initTable[string, tuple[path: string, ext: string]]()
  var includeFiles: seq[tuple[path: string, content: string]] = @[]

  for path in walkDirRec(normalized):
    let (_, fileName, ext) = splitFile(path)
    if ext != ".sql" and ext != ".nsql":
      continue

    # Include files go into the includes table, not scripts
    if isIncludeFile(fileName & ext):
      let content = staticRead(path)
      includeFiles.add((path, content))
      continue

    let relPath = relativePath(path, normalized)
    let (dirPart, name, _) = splitFile(relPath)
    var idPath =
      if dirPart.len == 0:
        name
      else:
        joinPath(dirPart, name)
    idPath = idPath.replace(DirSep, '/')
    if selected.hasKey(idPath):
      let existing = selected[idPath]
      if existing.ext == ext:
        error("Duplicate script id in embedSqlDir: " & idPath)
      if ext == ".sql":
        selected[idPath] = (path, ext)
    else:
      selected[idPath] = (path, ext)

  var ids: seq[string] = @[]
  for idPath in selected.keys:
    ids.add(idPath)
  ids.sort()

  var entries: seq[NimNode] = @[]
  for idPath in ids:
    let entry = selected[idPath]
    let sqlText = staticRead(entry.path)
    # Detect template: explicit .nsql extension OR auto-detect {#if in content
    let isTemplate = entry.ext == ".nsql" or hasTemplateContent(sqlText)
    # Compile the SQL at compile-time
    let compiled = compileNamedSql(sqlText)
    # Build the CompiledNamedSql object constructor
    var nameSetElements: seq[NimNode] = @[]
    for name in compiled.nameSet:
      nameSetElements.add newLit(name)
    let nameSetNode =
      if nameSetElements.len == 0:
        newCall(newTree(nnkBracketExpr, bindSym"initHashSet", ident"string"))
      else:
        newCall(bindSym"toHashSet", newTree(nnkBracket, nameSetElements))
    var namesNode = newTree(nnkPrefix, ident"@", newTree(nnkBracket))
    for name in compiled.names:
      namesNode[1].add newLit(name)
    let compiledNode = newTree(
      nnkObjConstr,
      ident"CompiledNamedSql",
      newTree(nnkExprColonExpr, ident"sql", newLit(compiled.sql)),
      newTree(nnkExprColonExpr, ident"names", namesNode),
      newTree(nnkExprColonExpr, ident"nameSet", nameSetNode),
    )
    entries.add newTree(
      nnkObjConstr,
      ident"Script",
      newTree(nnkExprColonExpr, ident"id", newLit(idPath)),
      newTree(nnkExprColonExpr, ident"sql", newLit(sqlText)),
      newTree(nnkExprColonExpr, ident"isTemplate", newLit(isTemplate)),
      newTree(nnkExprColonExpr, ident"origin", newLit(entry.path)),
      newTree(nnkExprColonExpr, ident"compiled", compiledNode),
    )

  # Build includes array
  var includesNode = newTree(nnkBracket)
  for (incPath, incContent) in includeFiles:
    includesNode.add newTree(nnkTupleConstr, newLit(incPath), newLit(incContent))

  result = newCall(
    ident"initEmbeddedScriptStore",
    newTree(nnkBracket, entries),
    includesNode,
    newLit(normalized),
  )
