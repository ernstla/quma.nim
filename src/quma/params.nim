import std/[strutils, sets]

import ./args
import ./errors

type CompiledNamedSql* = object
  sql*: string
  names*: seq[string]
  nameSet*: HashSet[string]

proc initCompiledNamedSql*(): CompiledNamedSql =
  ## Creates an empty CompiledNamedSql for uncompiled scripts.
  CompiledNamedSql(sql: "", names: @[], nameSet: initHashSet[string]())

proc compileNamedSql*(sql: string): CompiledNamedSql =
  var outSql = newStringOfCap(sql.len)
  var names: seq[string] = @[]
  var nameSet = initHashSet[string]()

  type State = enum
    stNormal
    stSingleQuote
    stDoubleQuote
    stLineComment
    stBlockComment

  var st = stNormal
  var i = 0
  while i < sql.len:
    let c = sql[i]

    case st
    of stNormal:
      if c == '\'':
        outSql.add c
        st = stSingleQuote
        inc i
        continue
      if c == '"':
        outSql.add c
        st = stDoubleQuote
        inc i
        continue
      if c == '-' and i + 1 < sql.len and sql[i + 1] == '-':
        outSql.add "--"
        st = stLineComment
        i += 2
        continue
      if c == '/' and i + 1 < sql.len and sql[i + 1] == '*':
        outSql.add "/*"
        st = stBlockComment
        i += 2
        continue

      if c == ':' and not (i > 0 and sql[i - 1] == ':'):
        if i + 1 < sql.len:
          let n0 = sql[i + 1]
          if n0.isAlphaAscii or n0 == '_':
            var j = i + 2
            while j < sql.len and
                (sql[j].isAlphaAscii or sql[j].isDigit or sql[j] == '_'):
              inc j

            let name = sql[(i + 1) ..< j]
            names.add name
            nameSet.incl name
            outSql.add '?'
            i = j
            continue

      outSql.add c
      inc i
    of stSingleQuote:
      if c == '\'' and i + 1 < sql.len and sql[i + 1] == '\'':
        outSql.add "''"
        i += 2
        continue

      outSql.add c
      inc i
      if c == '\'':
        st = stNormal
    of stDoubleQuote:
      if c == '"' and i + 1 < sql.len and sql[i + 1] == '"':
        outSql.add "\"\""
        i += 2
        continue

      outSql.add c
      inc i
      if c == '"':
        st = stNormal
    of stLineComment:
      outSql.add c
      inc i
      if c == '\n':
        st = stNormal
    of stBlockComment:
      if c == '*' and i + 1 < sql.len and sql[i + 1] == '/':
        outSql.add "*/"
        i += 2
        st = stNormal
      else:
        outSql.add c
        inc i

  CompiledNamedSql(sql: outSql, names: names, nameSet: nameSet)

proc raiseMissingParam*(name: string, scriptId: string) {.noreturn.} =
  raise newException(
    QueryError, "Missing required param '" & name & "' for script: " & scriptId
  )

proc quoteValue(v: ArgValue): string =
  ## Converts an ArgValue to a SQL-safe string representation for display.
  case v.kind
  of avkNull:
    "NULL"
  of avkInt:
    $v.i
  of avkFloat:
    $v.f
  of avkBool:
    if v.b: "1" else: "0"
  of avkString:
    "'" & v.s.replace("'", "''") & "'"

proc mogrify*(sql: string, bindValues: openArray[ArgValue]): string =
  ## Returns SQL with ? placeholders replaced by quoted values (for display only).
  ## This is NOT safe for execution - only for debugging output.
  var output = newStringOfCap(sql.len + bindValues.len * 10)
  var paramIdx = 0

  for c in sql:
    if c == '?' and paramIdx < bindValues.len:
      output.add quoteValue(bindValues[paramIdx])
      inc paramIdx
    else:
      output.add c

  output
