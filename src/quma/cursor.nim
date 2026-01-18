{.experimental: "dotOperators".}
{.experimental: "callOperator".}

import std/[macros, tables, sets]

import ./args
import ./database
import ./errors
import ./params
import ./query
import ./sqliteDb
import ./store

type
  Cursor* = ref object of CursorBase
    db: Database
    conn: SqliteConn

  NamespaceRef* = object
    cursor: CursorBase
    segments: seq[string]

  TypedScriptRef*[T] = object
    cursor: CursorBase
    scriptId: ScriptId
    rowMapper: RowMapper[T]

proc identNameOrError(node: NimNode, what: string): string =
  case node.kind
  of nnkIdent, nnkSym:
    result = node.strVal
  else:
    error("Expected " & what & " identifier, got: " & node.repr, node)

proc argKeyOrError(argNode: NimNode): string =
  identNameOrError(argNode, "named arg")

proc cursor*(db: Database): Cursor =
  let path = db.sqlitePathOrError()
  Cursor(db: db, conn: openSqlite(path))

proc database*(cur: Cursor): Database =
  cur.db

proc close*(cur: Cursor) =
  var c = cur.conn
  c.close()
  cur.conn = c

proc exec*(cur: Cursor, sqlText: string) =
  discard cur.conn.execPrepared(sqlText)

proc exec*(cur: Cursor, sqlText: string, bindValues: openArray[ArgValue]) =
  discard cur.conn.execPrepared(sqlText, bindValues)

proc initNamespaceRef*(cursor: CursorBase, segments: seq[string]): NamespaceRef =
  NamespaceRef(cursor: cursor, segments: segments)

proc initTypedScriptRef*[T](
    cursor: CursorBase, scriptId: ScriptId, rowMapper: RowMapper[T]
): TypedScriptRef[T] =
  TypedScriptRef[T](cursor: cursor, scriptId: scriptId, rowMapper: rowMapper)

macro `()`*(refExpr: TypedScriptRef, args: varargs[untyped]): untyped =
  let refSym = genSym(nskLet, "typedRef")
  let argsSym = genSym(nskVar, "scriptArgs")

  var argStmts = newStmtList()
  for arg in args:
    case arg.kind
    of nnkExprEqExpr, nnkExprColonExpr:
      let key = argKeyOrError(arg[0])
      let keyLit = newLit(key)
      argStmts.add newCall(
        bindSym"addNamed", argsSym, keyLit, newCall(bindSym"toArgValue", arg[1])
      )
    else:
      argStmts.add newCall(
        bindSym"addPositional", argsSym, newCall(bindSym"toArgValue", arg)
      )

  result = quote:
    block:
      let `refSym` = `refExpr`
      var `argsSym` = initScriptArgs()
      `argStmts`
      initQuery(`refSym`.cursor, `refSym`.scriptId, `argsSym`, `refSym`.rowMapper)

proc cursorBase*(ns: NamespaceRef): CursorBase =
  ns.cursor

proc segments*(ns: NamespaceRef): seq[string] =
  ns.segments

template `.`*(cur: Cursor, field: untyped): NamespaceRef =
  initNamespaceRef(cur, @[astToStr(field)])

template `.`*(ns: NamespaceRef, field: untyped): NamespaceRef =
  initNamespaceRef(ns.cursorBase, ns.segments & @[astToStr(field)])

type ScriptFieldInfo = object
  name: string
  typ: NimNode

proc fieldInfoOrError(fieldNode: NimNode): ScriptFieldInfo =
  case fieldNode.kind
  of nnkIdent, nnkSym:
    result = ScriptFieldInfo(name: fieldNode.strVal, typ: newEmptyNode())
  of nnkBracketExpr:
    if fieldNode.len != 2:
      error("Expected a single type parameter", fieldNode)
    let base = fieldNode[0]
    if base.kind notin {nnkIdent, nnkSym}:
      error("Expected script identifier", fieldNode)
    result = ScriptFieldInfo(name: base.strVal, typ: fieldNode[1])
  else:
    error("Expected field identifier", fieldNode)

proc queryInitCall(
    cursorExpr: NimNode, scriptIdExpr: NimNode, argsExpr: NimNode, info: ScriptFieldInfo
): NimNode =
  if info.typ.kind == nnkEmpty:
    newCall(bindSym"initQuery", cursorExpr, scriptIdExpr, argsExpr)
  else:
    let initSym = newTree(nnkBracketExpr, bindSym"initQuery", info.typ)
    let mapperSym = newTree(nnkBracketExpr, bindSym"fromRow", info.typ)
    newCall(initSym, cursorExpr, scriptIdExpr, argsExpr, mapperSym)

macro `.()`*(curExpr: Cursor, field: untyped, args: varargs[untyped]): untyped =
  let curSym = genSym(nskLet, "cur")
  let fieldInfo = fieldInfoOrError(field)
  let scriptIdLit = newLit(fieldInfo.name)
  let argsSym = genSym(nskVar, "scriptArgs")

  var argStmts = newStmtList()
  for arg in args:
    case arg.kind
    of nnkExprEqExpr, nnkExprColonExpr:
      let key = argKeyOrError(arg[0])
      let keyLit = newLit(key)
      argStmts.add newCall(
        bindSym"addNamed", argsSym, keyLit, newCall(bindSym"toArgValue", arg[1])
      )
    else:
      argStmts.add newCall(
        bindSym"addPositional", argsSym, newCall(bindSym"toArgValue", arg)
      )

  let queryCall = queryInitCall(curSym, scriptIdLit, argsSym, fieldInfo)
  result = quote:
    block:
      let `curSym` = `curExpr`
      var `argsSym` = initScriptArgs()
      `argStmts`
      `queryCall`

macro `.()`*(nsExpr: NamespaceRef, field: untyped, args: varargs[untyped]): untyped =
  let nsSym = genSym(nskLet, "ns")
  let fieldInfo = fieldInfoOrError(field)
  let scriptNameLit = newLit(fieldInfo.name)
  let argsSym = genSym(nskVar, "scriptArgs")

  var argStmts = newStmtList()
  for arg in args:
    case arg.kind
    of nnkExprEqExpr, nnkExprColonExpr:
      let key = argKeyOrError(arg[0])
      let keyLit = newLit(key)
      argStmts.add newCall(
        bindSym"addNamed", argsSym, keyLit, newCall(bindSym"toArgValue", arg[1])
      )
    else:
      argStmts.add newCall(
        bindSym"addPositional", argsSym, newCall(bindSym"toArgValue", arg)
      )

  let scriptIdExpr = newCall(
    bindSym"makeScriptId",
    newTree(
      nnkInfix,
      ident"&",
      newDotExpr(nsSym, ident"segments"),
      newTree(nnkPrefix, ident"@", newTree(nnkBracket, scriptNameLit)),
    ),
  )
  let queryCall = queryInitCall(
    newDotExpr(nsSym, ident"cursorBase"), scriptIdExpr, argsSym, fieldInfo
  )

  result = quote:
    block:
      let `nsSym` = `nsExpr`
      var `argsSym` = initScriptArgs()
      `argStmts`
      `queryCall`

macro `[]`*(nsExpr: NamespaceRef, typeNode: typedesc): untyped =
  let nsSym = genSym(nskLet, "ns")

  result = quote:
    block:
      let `nsSym` = `nsExpr`
      initTypedScriptRef(
        `nsSym`.cursorBase, makeScriptId(`nsSym`.segments), fromRow[`typeNode`]
      )

macro `[]`*(nsExpr: NamespaceRef, field: untyped, typeNode: typedesc): untyped =
  let nsSym = genSym(nskLet, "ns")
  let fieldInfo = fieldInfoOrError(field)
  let scriptNameLit = newLit(fieldInfo.name)
  let scriptIdExpr = newCall(
    bindSym"makeScriptId",
    newTree(
      nnkInfix,
      ident"&",
      newDotExpr(nsSym, ident"segments"),
      newTree(nnkPrefix, ident"@", newTree(nnkBracket, scriptNameLit)),
    ),
  )

  result = quote:
    block:
      let `nsSym` = `nsExpr`
      initTypedScriptRef(`nsSym`.cursorBase, `scriptIdExpr`, fromRow[`typeNode`])

method execute*(cur: Cursor, scriptId: ScriptId, scriptArgs: ScriptArgs): seq[Row] =
  let store = cur.db.scriptStore
  if store.isNil:
    raise newException(QumaError, "No ScriptStore configured")

  let script = store.getScript(scriptId)
  let compiled = compileNamedSql(script.sql)

  var filteredNamed = initTable[string, ArgValue]()
  for name in scriptArgs.named.keys:
    if name in compiled.nameSet:
      filteredNamed[name] = scriptArgs.named[name]

  var bindValues: seq[ArgValue] = @[]
  for name in compiled.names:
    if not filteredNamed.hasKey(name):
      raiseMissingParam(name, scriptId)
    bindValues.add filteredNamed[name]

  let rows = cur.conn.execPrepared(compiled.sql, bindValues)
  rows
