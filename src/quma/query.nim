import std/[options, sequtils, strutils, macros]
import ./args
import ./errors
import ./store

template qumaColumn*(name: string) {.pragma.}

type
  Row* = object
    columns*: seq[string]
    values*: seq[string]

  RowMapper*[T] = proc(row: Row): T

  CursorBase* = ref object of RootObj

proc `[]`*(row: Row, index: int): string =
  row.values[index]

proc len*(row: Row): int =
  row.values.len

macro accessField(obj: typed, name: static string): untyped =
  newDotExpr(obj, ident(name))

proc camelToSnake(name: string): string =
  result = ""
  for i, ch in name:
    if ch.isUpperAscii:
      if i > 0 and name[i - 1] != '_':
        result.add '_'
      result.add ch.toLowerAscii
    else:
      result.add ch

proc columnIndex(row: Row, name: string): int =
  let target = name.toLowerAscii
  for i, column in row.columns:
    if column.toLowerAscii == target:
      return i
  -1

template fieldColumnName(obj: typed, fieldName: static string): string =
  when accessField(obj, fieldName).hasCustomPragma(qumaColumn):
    accessField(obj, fieldName).getCustomPragmaVal(qumaColumn)
  else:
    camelToSnake(fieldName)

proc parseBoolValue(text: string, fieldName: string): bool =
  if text.len == 0:
    raise newException(QueryError, "Empty value for field '" & fieldName & "'")
  let lowered = text.toLowerAscii
  case lowered
  of "1", "true", "t", "yes", "y":
    true
  of "0", "false", "f", "no", "n":
    false
  else:
    raise newException(
      QueryError, "Invalid bool value '" & text & "' for field '" & fieldName & "'"
    )

proc parseIntValue[T: SomeInteger](text: string, fieldName: string): T =
  if text.len == 0:
    raise newException(QueryError, "Empty value for field '" & fieldName & "'")
  try:
    T(parseInt(text))
  except ValueError:
    raise newException(
      QueryError, "Invalid integer value '" & text & "' for field '" & fieldName & "'"
    )

proc parseFloatValue[T: SomeFloat](text: string, fieldName: string): T =
  if text.len == 0:
    raise newException(QueryError, "Empty value for field '" & fieldName & "'")
  try:
    T(parseFloat(text))
  except ValueError:
    raise newException(
      QueryError, "Invalid float value '" & text & "' for field '" & fieldName & "'"
    )

proc parseValue[T](text: string, fieldName: string): T =
  when T is string:
    result = text
  elif T is bool:
    result = parseBoolValue(text, fieldName)
  elif T is SomeInteger:
    result = parseIntValue[T](text, fieldName)
  elif T is SomeFloat:
    result = parseFloatValue[T](text, fieldName)
  else:
    {.error: "Unsupported field type for Quma mapping".}

proc assignField[T](value: var T, text: string, fieldName: string) =
  value = parseValue[T](text, fieldName)

proc fromRow*[T](row: Row): T =
  when T is Row:
    return row
  elif T is string or T is bool or T is SomeInteger or T is SomeFloat:
    if row.values.len == 0:
      raise newException(QueryError, "Query returned no columns")
    return parseValue[T](row.values[0], "value")
  elif T is object or T is tuple:
    var mapped: T
    for name, field in mapped.fieldPairs:
      let columnName = fieldColumnName(mapped, name)
      let index = columnIndex(row, columnName)
      if index < 0:
        raise newException(
          QueryError, "Missing column '" & columnName & "' for field '" & name & "'"
        )
      assignField(field, row.values[index], name)
    return mapped
  else:
    {.error: "Unsupported mapping type for Quma fromRow".}

method execute*(
    cursor: CursorBase, scriptId: ScriptId, scriptArgs: ScriptArgs
): seq[Row] {.base.} =
  raise newException(QumaError, "CursorBase.execute not implemented")

type Query*[T] = ref object
  cursor: CursorBase
  scriptId: ScriptId
  scriptArgs: ScriptArgs
  hasRun: bool
  rowCache: Option[seq[Row]]
  resultCache: Option[seq[T]]
  rowMapper: RowMapper[T]

proc identityRowMapper(row: Row): Row =
  row

proc initQuery*[T](
    cursor: CursorBase,
    scriptId: ScriptId,
    scriptArgs: ScriptArgs,
    rowMapper: RowMapper[T],
): Query[T] =
  if rowMapper.isNil:
    raise newException(QumaError, "Row mapper not provided")
  Query[T](
    cursor: cursor,
    scriptId: scriptId,
    scriptArgs: scriptArgs,
    hasRun: false,
    rowCache: none(seq[Row]),
    resultCache: none(seq[T]),
    rowMapper: rowMapper,
  )

proc initQuery*(
    cursor: CursorBase, scriptId: ScriptId, scriptArgs: ScriptArgs
): Query[Row] =
  initQuery[Row](cursor, scriptId, scriptArgs, identityRowMapper)

proc scriptId*[T](q: Query[T]): ScriptId =
  q.scriptId

proc scriptArgs*[T](q: Query[T]): ScriptArgs =
  q.scriptArgs

proc run*[T](q: Query[T]): Query[T] =
  let rows = q.cursor.execute(q.scriptId, q.scriptArgs)
  q.hasRun = true
  q.rowCache = some(rows)
  q.resultCache = none(seq[T])
  q

proc fetchRows[T](q: Query[T]): seq[Row] =
  if not q.hasRun:
    discard q.run()

  if q.rowCache.isNone:
    q.rowCache = some(newSeq[Row]())

  q.rowCache.get

proc fetch*[T](q: Query[T]): seq[T] =
  if q.resultCache.isNone:
    let mapped = q.fetchRows().mapIt(q.rowMapper(it))
    q.resultCache = some(mapped)

  q.resultCache.get

proc all*[T](q: Query[T]): seq[T] =
  q.fetch()

proc one*[T](q: Query[T]): T =
  let rows = q.fetchRows()
  if rows.len == 0:
    raise newException(QueryNoRowsError, "Query returned no rows")
  if rows.len > 1:
    raise newException(QueryTooManyRowsError, "Query returned multiple rows")
  q.rowMapper(rows[0])

proc first*[T](q: Query[T]): Option[T] =
  let rows = q.fetchRows()
  if rows.len == 0:
    return none(T)
  some(q.rowMapper(rows[0]))

proc exists*[T](q: Query[T]): bool =
  q.fetchRows().len > 0

proc count*[T](q: Query[T]): int =
  q.fetchRows().len
