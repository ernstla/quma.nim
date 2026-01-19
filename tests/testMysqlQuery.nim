## MySQL/MariaDB integration tests.
##
## These tests require:
## 1. Compile with -d:qumaMysql flag
## 2. Environment variables:
##    - QUMA_MYSQL_HOST (default: 127.0.0.1)
##    - QUMA_MYSQL_USER (default: quma)
##    - QUMA_MYSQL_PASSWORD (default: quma)
##    - QUMA_MYSQL_DATABASE (default: quma)
##    - QUMA_MYSQL_PORT (default: 3306)
##    - QUMA_MYSQL_SCHEME (default: mysql)
##
## Run with: nim r -d:qumaMysql tests/testMysqlQuery.nim

import unittest

when defined(qumaMysql):
  import std/[options, os, strutils]
  import quma

  proc getMysqlUri(): string =
    ## Builds a mysql:// URI from environment variables.
    let host = getEnv("QUMA_MYSQL_HOST", "127.0.0.1")
    let user = getEnv("QUMA_MYSQL_USER", "quma")
    let pass = getEnv("QUMA_MYSQL_PASSWORD", "quma")
    let db = getEnv("QUMA_MYSQL_DATABASE", "quma")
    let port = getEnv("QUMA_MYSQL_PORT", "3306")
    let scheme = getEnv("QUMA_MYSQL_SCHEME", "mysql")

    let normalizedScheme = scheme.toLowerAscii()
    if normalizedScheme notin ["mysql", "mariadb"]:
      return ""

    if host.len == 0 or user.len == 0 or db.len == 0:
      return ""

    result = normalizedScheme & "://" & user
    if pass.len > 0:
      result.add ":" & pass
    result.add "@" & host & ":" & port & "/" & db

  let myUri = getMysqlUri()
  let skipTests = myUri.len == 0

  type UserId = object
    id: int

  type UserProfile = object
    id {.qumaColumn: "user_id".}: int
    name: string

  suite "MySQL Query":
    if skipTests:
      echo "Skipping MySQL tests: missing QUMA_MYSQL_HOST, QUMA_MYSQL_USER, or QUMA_MYSQL_DATABASE env vars"

    test "can execute script and fetch helpers":
      if skipTests:
        skip()
      else:
        let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/mysql")
        let store = initFsScriptStore([sqlDir])

        let db = initDatabase(myUri, store)
        let cur = db.cursor()

        cur.exec("drop table if exists users;")
        cur.exec("create table users(id int, name text);")
        cur.exec("insert into users(id, name) values (1, 'Ada');")
        cur.exec("insert into users(id, name) values (2, 'Bob');")

        expect QueryNoRowsError:
          discard cur.users.getById(id = 999, name = "Ada").one()

        expect QueryTooManyRowsError:
          discard cur.users.all().one()

        cur.exec("drop table users;")

    test "named param compilation to positional binds":
      if skipTests:
        skip()
      else:
        let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/mysql")
        let store = initFsScriptStore([sqlDir])
        let db = initDatabase(myUri, store)
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
      if skipTests:
        skip()
      else:
        let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/mysql")
        let store = initFsScriptStore([sqlDir])
        let db = initDatabase(myUri, store)
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
  suite "MySQL Query (disabled)":
    test "mysql backend not compiled":
      echo "MySQL tests disabled: compile with -d:qumaMysql to enable"
      skip()
