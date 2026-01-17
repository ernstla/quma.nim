{.experimental: "dotOperators".}

import std/macros

import ./args
import ./database
import ./query
import ./store

type
  Cursor* = ref object of CursorBase
    db: Database

  NamespaceRef* = object
    cursor: CursorBase
    segments: seq[string]

  ScriptRef* = object
    cursor: CursorBase
    segments: seq[string]

proc cursor*(db: Database): Cursor =
  Cursor(db: db)

proc database*(cur: Cursor): Database =
  cur.db

proc initNamespaceRef*(cursor: CursorBase, segments: seq[string]): NamespaceRef =
  NamespaceRef(cursor: cursor, segments: segments)

proc initScriptRef*(cursor: CursorBase, segments: seq[string]): ScriptRef =
  ScriptRef(cursor: cursor, segments: segments)

proc cursorBase*(ns: NamespaceRef): CursorBase =
  ns.cursor

proc segments*(ns: NamespaceRef): seq[string] =
  ns.segments

proc cursorBase*(sr: ScriptRef): CursorBase =
  sr.cursor

proc segments*(sr: ScriptRef): seq[string] =
  sr.segments

proc scriptId*(sr: ScriptRef): ScriptId =
  makeScriptId(sr.segments)

template `.`*(cur: Cursor, field: untyped): NamespaceRef =
  initNamespaceRef(cur, @[astToStr(field)])

template `.`*(ns: NamespaceRef, field: untyped): ScriptRef =
  initScriptRef(ns.cursorBase, ns.segments & @[astToStr(field)])

template `.`*(sr: ScriptRef, field: untyped): ScriptRef =
  initScriptRef(sr.cursorBase, sr.segments & @[astToStr(field)])

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
