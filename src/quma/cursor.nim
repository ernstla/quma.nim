{.experimental: "dotOperators".}

import std/macros
import std/tables

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

proc cursorBase*(ns: NamespaceRef): CursorBase =
  ns.cursor

proc segments*(ns: NamespaceRef): seq[string] =
  ns.segments

template `.`*(cur: Cursor, field: untyped): NamespaceRef =
  initNamespaceRef(cur, @[astToStr(field)])

template `.`*(ns: NamespaceRef, field: untyped): NamespaceRef =
  initNamespaceRef(ns.cursorBase, ns.segments & @[astToStr(field)])

proc identNameOrError(node: NimNode, what: string): string =
  case node.kind
  of nnkIdent, nnkSym:
    node.strVal
  else:
    error("Expected " & what & " identifier, got: " & node.repr, node)

proc argKeyOrError(argNode: NimNode): string =
  identNameOrError(argNode, "named arg")

proc fieldNameOrError(fieldNode: NimNode): string =
  identNameOrError(fieldNode, "field")

macro `.()`*(curExpr: Cursor, field: untyped, args: varargs[untyped]): untyped =
  let curSym = genSym(nskLet, "cur")
  let scriptIdLit = newLit(fieldNameOrError(field))
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
      let `curSym` = `curExpr`
      var `argsSym` = initScriptArgs()
      `argStmts`
      initQuery(`curSym`, `scriptIdLit`, `argsSym`)

macro `.()`*(nsExpr: NamespaceRef, field: untyped, args: varargs[untyped]): untyped =
  let nsSym = genSym(nskLet, "ns")
  let scriptNameLit = newLit(fieldNameOrError(field))
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
      let `nsSym` = `nsExpr`
      var `argsSym` = initScriptArgs()
      `argStmts`
      initQuery(
        `nsSym`.cursorBase,
        makeScriptId(`nsSym`.segments & @[`scriptNameLit`]),
        `argsSym`,
      )

method execute*(cur: Cursor, scriptId: ScriptId, scriptArgs: ScriptArgs): seq[Row] =
  let store = cur.db.scriptStore
  if store.isNil:
    raise newException(QumaError, "No ScriptStore configured")

  let script = store.getScript(scriptId)
  let compiled = compileNamedSql(script.sql)

  var bindValues: seq[ArgValue] = @[]
  for name in compiled.names:
    if not scriptArgs.named.hasKey(name):
      raiseMissingParam(name, scriptId)
    bindValues.add scriptArgs.named[name]

  let rows = cur.conn.execPrepared(compiled.sql, bindValues)
  rows
