## SQLite backend implementation.

import std/sequtils

import db_connector/db_sqlite as sqlite

import ../args
import ../backend as qumaBackend
import ../errors

type
  SqliteBackend* = ref object of DbBackend

  SqliteConnection* = ref object of DbConnection
    handle*: sqlite.DbConn

proc initSqliteBackend*(): SqliteBackend =
  SqliteBackend()

proc parseUri(uri: string): string =
  ## Parses a sqlite:// URI and returns the database path.
  if uri == "sqlite:///:memory:":
    return ":memory:"

  if uri.len > 10 and uri[0 ..< 10] == "sqlite:///":
    return uri[10 .. ^1]

  raise newException(QumaError, "Invalid SQLite URI: " & uri)

method placeholderStyle*(backend: SqliteBackend): PlaceholderStyle =
  psQuestionMark

method openConnection*(backend: SqliteBackend, uri: string): DbConnection =
  let path = parseUri(uri)
  let db = sqlite.open(path, "", "", "")
  SqliteConnection(handle: db)

method closeConnection*(backend: SqliteBackend, conn: DbConnection) =
  let sqliteConn = SqliteConnection(conn)
  if sqliteConn.handle != nil:
    sqliteConn.handle.close()
    sqliteConn.handle = nil

proc toBindArgs(bindValues: seq[ArgValue]): seq[string] =
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

method execPrepared*(
    backend: SqliteBackend, conn: DbConnection, sql: string, bindValues: seq[ArgValue]
): seq[qumaBackend.Row] =
  let sqliteConn = SqliteConnection(conn)
  if sqliteConn.handle == nil:
    raise newException(QumaError, "SQLite connection not open")

  var columns: sqlite.DbColumns
  var rows: seq[qumaBackend.Row] = @[]
  let q = sqlite.sql(sql)
  for row in sqliteConn.handle.instantRows(columns, q, toBindArgs(bindValues)):
    var values = newSeq[string](row.len)
    for i in 0 ..< values.len:
      values[i] = row[int32(i)]
    rows.add qumaBackend.Row(columns: columns.mapIt(it.name), values: values)
  rows
