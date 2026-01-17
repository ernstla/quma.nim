import std/options

import ./args
import ./errors
import ./store

type
  Row* = seq[string]

  CursorBase* = ref object of RootObj

method execute*(
    cursor: CursorBase, scriptId: ScriptId, scriptArgs: ScriptArgs
): seq[Row] {.base.} =
  raise newException(QumaError, "CursorBase.execute not implemented")

type Query* = ref object
  cursor: CursorBase
  scriptId: ScriptId
  scriptArgs: ScriptArgs
  hasRun: bool
  resultCache: Option[seq[Row]]

proc initQuery*(cursor: CursorBase, scriptId: ScriptId, scriptArgs: ScriptArgs): Query =
  Query(
    cursor: cursor,
    scriptId: scriptId,
    scriptArgs: scriptArgs,
    hasRun: false,
    resultCache: none(seq[Row]),
  )

proc scriptId*(q: Query): ScriptId =
  q.scriptId

proc scriptArgs*(q: Query): ScriptArgs =
  q.scriptArgs

proc run*(q: Query): Query =
  let rows = q.cursor.execute(q.scriptId, q.scriptArgs)
  q.hasRun = true
  q.resultCache = some(rows)
  q

proc fetch*(q: Query): seq[Row] =
  if not q.hasRun:
    discard q.run()

  if q.resultCache.isNone:
    q.resultCache = some(newSeq[Row]())

  q.resultCache.get

proc all*(q: Query): seq[Row] =
  q.fetch()

proc one*(q: Query): Row =
  let rows = q.fetch()
  if rows.len == 0:
    raise newException(QueryNoRowsError, "Query returned no rows")
  if rows.len > 1:
    raise newException(QueryTooManyRowsError, "Query returned multiple rows")
  rows[0]

proc first*(q: Query): Option[Row] =
  let rows = q.fetch()
  if rows.len == 0:
    return none(Row)
  some(rows[0])

proc exists*(q: Query): bool =
  q.fetch().len > 0

proc count*(q: Query): int =
  q.fetch().len
