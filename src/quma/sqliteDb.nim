import std/sequtils

import db_connector/db_sqlite as sqlite

import ./args
import ./errors
import ./query

type SqliteConn* = object
  handle*: sqlite.DbConn

proc isOpen*(c: SqliteConn): bool =
  c.handle != nil

proc openSqlite*(path: string): SqliteConn =
  let db = sqlite.open(path, "", "", "")
  SqliteConn(handle: db)

proc close*(c: var SqliteConn) =
  if c.handle != nil:
    c.handle.close()
    c.handle = nil

proc toBindArgs(bindValues: openArray[ArgValue]): seq[string] =
  result = @[]
  for v in bindValues:
    case v.kind
    of avkNull:
      result.add ""
    of avkInt:
      result.add $v.i
    of avkFloat:
      result.add $v.f
    of avkString:
      result.add v.s
    of avkBool:
      result.add (if v.b: "1" else: "0")

proc execPrepared*(
    c: SqliteConn, sqlText: string, bindValues: openArray[ArgValue]
): seq[query.Row] =
  if c.handle == nil:
    raise newException(QumaError, "SQLite connection not open")

  var columns: sqlite.DbColumns
  var rows: seq[query.Row] = @[]
  let q = sqlite.sql(sqlText)
  for row in c.handle.instantRows(columns, q, toBindArgs(bindValues)):
    var values = newSeq[string](row.len)
    for i in 0 ..< values.len:
      values[i] = row[int32(i)]
    rows.add query.Row(columns: columns.mapIt(it.name), values: values)
  rows

proc execPrepared*(c: SqliteConn, sqlText: string): seq[query.Row] =
  c.execPrepared(sqlText, newSeq[ArgValue]())
