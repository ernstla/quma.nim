import std/strutils

import ./args
import ./errors
import ./sqlCompile

export sqlCompile

# Alias for backward compatibility
type CompiledNamedSql* = CompiledSql

proc initCompiledNamedSql*(): CompiledNamedSql =
  initCompiledSql()

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
  ## Returns SQL with ? or $n placeholders replaced by quoted values (for display only).
  ## This is NOT safe for execution - only for debugging output.
  var output = newStringOfCap(sql.len + bindValues.len * 10)
  var paramIdx = 0
  var i = 0

  while i < sql.len:
    let c = sql[i]
    # Handle ? placeholders
    if c == '?' and paramIdx < bindValues.len:
      output.add quoteValue(bindValues[paramIdx])
      inc paramIdx
      inc i
    # Handle $n placeholders (PostgreSQL style)
    elif c == '$' and i + 1 < sql.len and sql[i + 1].isDigit:
      var j = i + 1
      while j < sql.len and sql[j].isDigit:
        inc j
      let numStr = sql[i + 1 ..< j]
      let num = parseInt(numStr) - 1 # $1 is index 0
      if num >= 0 and num < bindValues.len:
        output.add quoteValue(bindValues[num])
      else:
        output.add sql[i ..< j]
      i = j
    else:
      output.add c
      inc i

  output
