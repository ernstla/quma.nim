## SQL compilation utilities.
##
## This module handles converting named parameters (:name) to positional
## placeholders (? or $n) based on the backend's style.

import std/[sets, strutils]

type
  PlaceholderStyle* = enum
    ## How named parameters are converted to positional placeholders.
    psQuestionMark ## ? (SQLite, MySQL)
    psDollarNumber ## $1, $2, ... (PostgreSQL)

  CompiledSql* = object
    sql*: string
    names*: seq[string]
    nameSet*: HashSet[string]

proc initCompiledSql*(): CompiledSql =
  ## Creates an empty CompiledSql for uncompiled scripts.
  CompiledSql(sql: "", names: @[], nameSet: initHashSet[string]())

proc compileNamedSql*(sql: string, style: PlaceholderStyle): CompiledSql =
  ## Compiles named parameters (:name) to positional placeholders.
  ## The placeholder format depends on the backend's style.
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
  var paramIndex = 0

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
            inc paramIndex

            case style
            of psQuestionMark:
              outSql.add '?'
            of psDollarNumber:
              outSql.add '$'
              outSql.add $paramIndex

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

  CompiledSql(sql: outSql, names: names, nameSet: nameSet)

proc compileNamedSql*(sql: string): CompiledSql =
  ## Compile with default ? placeholders (for compile-time embedding)
  compileNamedSql(sql, psQuestionMark)
