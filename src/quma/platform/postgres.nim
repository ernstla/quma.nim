## PostgreSQL backend implementation.

import std/[sequtils, strutils]
import std/uri as stdUri

import db_connector/db_postgres as postgres

import ../args
import ../backend as qumaBackend
import ../errors

type
  PostgresBackend* = ref object of DbBackend

  PostgresConnection* = ref object of DbConnection
    handle*: postgres.DbConn

proc initPostgresBackend*(): PostgresBackend =
  PostgresBackend()

proc parsePostgresUri(
    uriStr: string
): tuple[host: string, user: string, pass: string, db: string] =
  ## Parses a postgres:// URI and returns connection parameters.
  ## Format: postgres://user:password@host:port/database
  if not uriStr.startsWith("postgres://"):
    raise newException(QumaError, "Invalid PostgreSQL URI: " & uriStr)

  let parsed = stdUri.parseUri(uriStr)

  var host = parsed.hostname
  if parsed.port.len > 0:
    host = host & ":" & parsed.port

  result = (
    host: host,
    user: parsed.username,
    pass: parsed.password,
    db: parsed.path.strip(chars = {'/'}),
  )

method placeholderStyle*(backend: PostgresBackend): PlaceholderStyle =
  psDollarNumber

method openConnection*(backend: PostgresBackend, uri: string): DbConnection =
  let params = parsePostgresUri(uri)
  let db = postgres.open(params.host, params.user, params.pass, params.db)
  PostgresConnection(handle: db)

method closeConnection*(backend: PostgresBackend, conn: DbConnection) =
  let pgConn = PostgresConnection(conn)
  if pgConn.handle != nil:
    pgConn.handle.close()

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
      # PostgreSQL uses 't'/'f' or 'true'/'false' for booleans
      result.add (if v.b: "t" else: "f")

method execPrepared*(
    backend: PostgresBackend, conn: DbConnection, sql: string, bindValues: seq[ArgValue]
): seq[qumaBackend.Row] =
  let pgConn = PostgresConnection(conn)
  if pgConn.handle == nil:
    raise newException(QumaError, "PostgreSQL connection not open")

  var columns: postgres.DbColumns
  var rows: seq[qumaBackend.Row] = @[]

  # Use instantRows with column info to get column names
  for row in pgConn.handle.instantRows(columns, sql(sql), toBindArgs(bindValues)):
    var values = newSeq[string](row.len)
    for i in 0 ..< row.len:
      values[i] = row[i]
    rows.add qumaBackend.Row(columns: columns.mapIt(it.name), values: values)

  rows
