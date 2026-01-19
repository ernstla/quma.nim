{.experimental: "dotOperators".}
{.experimental: "callOperator".}

import std/[macros, os, tables, sets, strutils]

import ./args
import ./errors
import ./params
import ./query
import ./sqliteDb
import ./store
import ./tmplEval

import ./database

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

proc echoSql(cur: Cursor, sql: string) =
  ## Prints SQL to stdout if echo is enabled on the database.
  if cur.db.echo:
    echo "-".repeat(50)
    echo sql

proc echoSql(cur: Cursor, sql: string, bindValues: openArray[ArgValue]) =
  ## Prints mogrified SQL to stdout if echo is enabled on the database.
  if cur.db.echo:
    echo "-".repeat(50)
    echo mogrify(sql, bindValues)

proc exec*(cur: Cursor, sqlText: string) =
  ## Executes SQL without returning results.
  discard cur.conn.execPrepared(sqlText)
  cur.echoSql(sqlText)

proc exec*(cur: Cursor, sqlText: string, bindValues: openArray[ArgValue]) =
  ## Executes SQL with bind values, without returning results.
  discard cur.conn.execPrepared(sqlText, bindValues)
  cur.echoSql(sqlText, bindValues)

proc rawQuery*(cur: Cursor, sqlText: string): seq[Row] =
  ## Executes raw SQL and returns rows. For testing and low-level access.
  result = cur.conn.execPrepared(sqlText)
  cur.echoSql(sqlText)

proc rawQuery*(
    cur: Cursor, sqlText: string, bindValues: openArray[ArgValue]
): seq[Row] =
  ## Executes raw SQL with bind values and returns rows. For testing and low-level access.
  result = cur.conn.execPrepared(sqlText, bindValues)
  cur.echoSql(sqlText, bindValues)

proc begin*(cur: Cursor) =
  ## Begins a transaction.
  ## Note: Currently uses SQLite syntax. Other backends (PostgreSQL, MySQL)
  ## may require different commands (e.g., START TRANSACTION).
  cur.exec("begin")

proc commit*(cur: Cursor) =
  ## Commits the current transaction.
  cur.exec("commit")

proc rollback*(cur: Cursor) =
  ## Rolls back the current transaction.
  cur.exec("rollback")

template transaction*(cur: Cursor, body: untyped) =
  ## Executes `body` within a transaction. Commits on success, rolls back on
  ## any error (including Defects) to ensure connections aren't left with
  ## open transactions — important for connection-pooled databases.
  cur.begin()
  try:
    body
    cur.commit()
  except:
    cur.rollback()
    raise

proc withCursor*(db: Database, body: proc(c: Cursor)) =
  ## Opens a cursor, executes body, and closes the cursor on exit.
  ##
  ## Example:
  ##   db.withCursor do(c: Cursor):
  ##     discard c.users.all().run()
  ##   # cursor is closed here
  let c = db.cursor()
  try:
    body(c)
  finally:
    c.close()

proc withCursor*(db: Database, commit: bool, body: proc(c: Cursor)) =
  ## Opens a cursor with optional auto-commit on successful exit.
  ## If `commit = true`, wraps body in a transaction: commits on success, rolls back on error.
  ## The cursor is always closed on exit (success or failure).
  ##
  ## Example:
  ##   db.withCursor(commit = true) do(c: Cursor):
  ##     c.users.add(name = "Alice").run()
  ##   # auto-committed on success, rolled back on error
  let c = db.cursor()
  if commit:
    try:
      c.begin()
      body(c)
      c.commit()
    except:
      c.rollback()
      raise
    finally:
      c.close()
  else:
    try:
      body(c)
    finally:
      c.close()

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

  # Strict mode: error if template syntax found in .sql file
  if cur.db.strictTemplates and script.isTemplate and script.origin.endsWith(".sql"):
    raise newException(
      TemplateError,
      script.origin &
        ": Template syntax in .sql file; use .nsql extension or disable strictTemplates",
    )

  # For templates, render first then compile the result
  let compiled =
    if script.isTemplate:
      # Create include resolver that uses the store
      let scriptDir = splitFile(script.origin).dir
      proc resolver(path: string, currentDir: string): string =
        store.resolveInclude(path, currentDir)

      let renderedSql =
        renderTemplate(script.sql, scriptArgs.named, script.origin, scriptDir, resolver)
      compileNamedSql(renderedSql)
    else:
      script.compiled

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
  cur.echoSql(compiled.sql, bindValues)
  rows
