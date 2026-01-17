import std/sequtils

import db_connector/db_sqlite

import ./args
import ./errors

type SqliteConn* = object
  handle*: DbConn

proc isOpen*(c: SqliteConn): bool =
  c.handle != nil

proc openSqlite*(path: string): SqliteConn =
  let db = db_sqlite.open(path, "", "", "")
  SqliteConn(handle: db)

proc close*(c: var SqliteConn) =
  if c.handle != nil:
    c.handle.close()
    c.handle = nil

proc execPrepared*(
    c: SqliteConn, sqlText: string, bindValues: openArray[ArgValue]
): seq[seq[string]] =
  if c.handle == nil:
    raise newException(QumaError, "SQLite connection not open")

  var args: seq[string] = @[]
  for v in bindValues:
    case v.kind
    of avkNull:
      args.add ""
    of avkInt:
      args.add $v.i
    of avkFloat:
      args.add $v.f
    of avkString:
      args.add v.s
    of avkBool:
      args.add (if v.b: "1" else: "0")

  let q = sql(sqlText)
  c.handle.getAllRows(q, args).mapIt(@it)

proc execPrepared*(c: SqliteConn, sqlText: string): seq[seq[string]] =
  c.execPrepared(sqlText, newSeq[ArgValue]())
