## Backend abstraction for database connections.
##
## Each backend (SQLite, PostgreSQL, etc.) implements this interface
## to provide database-specific connection handling and query execution.

import ./args
import ./sqlCompile

export sqlCompile

type
  Row* = object
    columns*: seq[string]
    values*: seq[string]

  DbBackend* = ref object of RootObj
    ## Base type for database backends.
    ## Each backend implements the abstract methods below.

  DbConnection* = ref object of RootObj
    ## Base type for database connections.
    ## Backend-specific connection types inherit from this.

proc `[]`*(row: Row, index: int): string =
  row.values[index]

proc len*(row: Row): int =
  row.values.len

# Backend interface methods

method placeholderStyle*(backend: DbBackend): PlaceholderStyle {.base.} =
  ## Returns the placeholder style used by this backend.
  psQuestionMark

method openConnection*(backend: DbBackend, uri: string): DbConnection {.base.} =
  ## Opens a connection to the database specified by the URI.
  raise newException(Defect, "DbBackend.openConnection not implemented")

method closeConnection*(backend: DbBackend, conn: DbConnection) {.base.} =
  ## Closes the database connection.
  raise newException(Defect, "DbBackend.closeConnection not implemented")

method execPrepared*(
    backend: DbBackend, conn: DbConnection, sql: string, bindValues: seq[ArgValue]
): seq[Row] {.base.} =
  ## Executes a prepared statement with bind values and returns rows.
  raise newException(Defect, "DbBackend.execPrepared not implemented")
