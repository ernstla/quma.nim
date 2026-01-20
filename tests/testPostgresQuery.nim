## PostgreSQL integration tests.
##
## These tests require:
## 1. Compile with -d:qumaPostgres flag
## 2. A running Postgres instance reachable via:
##    - QUMA_PGSQL_HOST (default: localhost)
##    - QUMA_PGSQL_USER (default: quma)
##    - QUMA_PGSQL_PASSWORD (default: quma)
##    - QUMA_PGSQL_DATABASE (default: quma)
##    - QUMA_PGSQL_PORT (default: 5432)
##
## Run with: nim r -d:qumaPostgres tests/testPostgresQuery.nim

import unittest

when defined(qumaPostgres):
  import std/[options, os]
  import quma

  proc getPostgresUri(): string =
    ## Builds a postgres:// URI from environment variables.
    let host = getEnv("QUMA_PGSQL_HOST", "localhost")
    let user = getEnv("QUMA_PGSQL_USER", "quma")
    let pass = getEnv("QUMA_PGSQL_PASSWORD", "quma")
    let db = getEnv("QUMA_PGSQL_DATABASE", "quma")
    let port = getEnv("QUMA_PGSQL_PORT", "5432")

    result = "postgres://" & user
    if pass.len > 0:
      result.add ":" & pass
    result.add "@" & host & ":" & port & "/" & db

  let pgUri = getPostgresUri()

  type UserId = object
    id: int

  type UserProfile = object
    id {.qumaColumn: "user_id".}: int
    name: string

  suite "PostgreSQL Query":
    test "can execute script and fetch helpers":
      let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/postgres")
      let store = initFsScriptStore([sqlDir])

      let db = initDatabase(pgUri, store)
      let cur = db.cursor()

      # Setup - use temp table to avoid polluting database
      cur.exec("drop table if exists users;")
      cur.exec("create table users(id int, name text);")
      cur.exec("insert into users(id, name) values (1, 'Ada');")
      cur.exec("insert into users(id, name) values (2, 'Bob');")

      expect QueryNoRowsError:
        discard cur.users.getById(id = 999, name = "Ada").one()

      expect QueryTooManyRowsError:
        discard cur.users.all().one()

      # Cleanup
      cur.exec("drop table users;")

    test "named param compilation to positional binds":
      let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/postgres")
      let store = initFsScriptStore([sqlDir])
      let db = initDatabase(pgUri, store)
      let cur = db.cursor()

      cur.exec("drop table if exists users;")
      cur.exec("create table users(id int, name text);")
      cur.exec("insert into users(id, name) values (1, 'Ada');")
      cur.exec("insert into users(id, name) values (2, 'Bob');")

      let r = cur.users.getById(id = 1, name = "Ada", extra = "ignore").one()
      check r[0] == "1"

      expect QueryError:
        discard cur.users.getById().one()

      cur.exec("drop table users;")

    test "typed query mapping":
      let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/postgres")
      let store = initFsScriptStore([sqlDir])
      let db = initDatabase(pgUri, store)
      let cur = db.cursor()

      cur.exec("drop table if exists users;")
      cur.exec("create table users(id int, name text);")
      cur.exec("insert into users(id, name) values (1, 'Ada');")
      cur.exec("insert into users(id, name) values (2, 'Bob');")

      let ids = cur.users.all[UserId]().all()
      check ids.len == 2
      check ids[0].id == 1

      let profile = cur.users.allProfiles[UserProfile]().first()
      check profile.isSome
      check profile.get.id == 1
      check profile.get.name == "Ada"

      let missing = cur.users.getById(id = 999, name = "Ada").first()
      check missing.isNone

      cur.exec("drop table users;")
else:
  # When qumaPostgres is not defined, provide a stub so the test file compiles
  suite "PostgreSQL Query (disabled)":
    test "postgres backend not compiled":
      echo "PostgreSQL tests disabled: compile with -d:qumaPostgres to enable"
      skip()
