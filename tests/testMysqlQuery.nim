## MySQL/MariaDB integration tests.
##
## These tests require:
## 1. Compile with -d:qumaMysql flag
## 2. Environment variables: MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE
##
## Run with: nim r -d:qumaMysql tests/testMysqlQuery.nim

import std/[options, os, strutils]
import unittest

when defined(qumaMysql):
  import quma

  proc getMysqlUri(): string =
    ## Builds a mysql:// URI from environment variables.
    let host = getEnv("MYSQL_HOST", "")
    let user = getEnv("MYSQL_USER", "")
    let pass = getEnv("MYSQL_PASSWORD", "")
    let db = getEnv("MYSQL_DATABASE", "")
    let port = getEnv("MYSQL_PORT", "3306")
    let scheme = getEnv("MYSQL_SCHEME", "mysql")

    if host.len == 0 or user.len == 0 or db.len == 0:
      return ""

    let normalizedScheme = scheme.toLowerAscii()
    if normalizedScheme notin ["mysql", "mariadb"]:
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
      echo "Skipping MySQL tests: missing MYSQL_HOST, MYSQL_USER, MYSQL_DATABASE env vars"

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
  import unittest

  suite "MySQL Query (disabled)":
    test "mysql backend not compiled":
      echo "MySQL tests disabled: compile with -d:qumaMysql to enable"
      skip()
