## MySQL/MariaDB backend implementation.

import std/[sequtils, strutils]
import std/uri as stdUri

import db_connector/db_mysql as mysql

import ../args
import ../backend as qumaBackend
import ../errors

type
  MysqlBackend* = ref object of DbBackend

  MysqlConnection* = ref object of DbConnection
    handle*: mysql.DbConn

proc initMysqlBackend*(): MysqlBackend =
  MysqlBackend()

proc parseMysqlUri(
    uriStr: string
): tuple[host: string, user: string, pass: string, db: string] =
  ## Parses a mysql:// or mariadb:// URI and returns connection parameters.
  ## Format: mysql://user:password@host:port/database
  let parsed = stdUri.parseUri(uriStr)
  if parsed.scheme notin ["mysql", "mariadb"]:
    raise newException(QumaError, "Invalid MySQL URI: " & uriStr)

  var host = parsed.hostname
  if parsed.port.len > 0:
    host = host & ":" & parsed.port

  result = (
    host: host,
    user: parsed.username,
    pass: parsed.password,
    db: parsed.path.strip(chars = {'/'}),
  )

method placeholderStyle*(backend: MysqlBackend): PlaceholderStyle =
  psQuestionMark

method openConnection*(backend: MysqlBackend, uri: string): DbConnection =
  let params = parseMysqlUri(uri)
  let db = mysql.open(params.host, params.user, params.pass, params.db)
  MysqlConnection(handle: db)

method closeConnection*(backend: MysqlBackend, conn: DbConnection) =
  let myConn = MysqlConnection(conn)
  if cast[pointer](myConn.handle) != nil:
    myConn.handle.close()
    myConn.handle = mysql.DbConn(nil)

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
    backend: MysqlBackend, conn: DbConnection, sql: string, bindValues: seq[ArgValue]
): seq[qumaBackend.Row] =
  let myConn = MysqlConnection(conn)
  if cast[pointer](myConn.handle) == nil:
    raise newException(QumaError, "MySQL connection not open")

  var columns: mysql.DbColumns
  var rows: seq[qumaBackend.Row] = @[]
  let q = mysql.sql(sql)

  for row in myConn.handle.instantRows(columns, q, toBindArgs(bindValues)):
    var values = newSeq[string](row.len)
    for i in 0 ..< row.len:
      values[i] = row[i]
    rows.add qumaBackend.Row(columns: columns.mapIt(it.name), values: values)

  rows
