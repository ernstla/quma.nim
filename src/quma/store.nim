import std/[algorithm, os, strutils, tables, sets]
import std/macros

import ./errors
import ./params

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
    namespaces: HashSet[string]

  OverlayScriptStore* = ref object of ScriptStore
    primary: ScriptStore
    fallback: ScriptStore

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

proc initEmbeddedScriptStore*(entries: openArray[Script]): EmbeddedScriptStore =
  result = EmbeddedScriptStore(
    scripts: initTable[ScriptId, Script](), namespaces: initHashSet[string]()
  )
  for entry in entries:
    result.scripts[entry.id] = entry
    result.addNamespaces(entry.id)

proc initOverlayScriptStore*(
    primary: ScriptStore, fallback: ScriptStore
): OverlayScriptStore =
  OverlayScriptStore(primary: primary, fallback: fallback)

method hasNamespace*(store: ScriptStore, name: string): bool {.base.} =
  false

method getScript*(store: ScriptStore, id: ScriptId): Script {.base.} =
  raise newException(QumaError, "ScriptStore.getScript not implemented")

method hasNamespace*(store: EmbeddedScriptStore, name: string): bool =
  store.namespaces.contains(name)

method getScript*(store: EmbeddedScriptStore, id: ScriptId): Script =
  if store.scripts.hasKey(id):
    return store.scripts[id]
  raise newException(ScriptNotFoundError, "Script not found: " & id)

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
  var selected = initTable[string, tuple[path: string, ext: string]]()
  for path in walkDirRec(normalized):
    let ext = splitFile(path).ext
    if ext != ".sql" and ext != ".nsql":
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
    let isTemplate = entry.ext == ".nsql"
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
  result = newCall(ident"initEmbeddedScriptStore", newTree(nnkBracket, entries))
