import std/os
import unittest

import quma

suite "SQLite Query":
  test "can execute script and fetch helpers":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])

    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int);")
    cur.exec("insert into users(id) values (1);")
    cur.exec("insert into users(id) values (2);")

    expect QueryNoRowsError:
      discard cur.users.get_by_id(id = 999).one()

    expect QueryTooManyRowsError:
      discard cur.users.all().one()

  test "named param compilation to positional binds":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int);")
    cur.exec("insert into users(id) values (1);")

    let r = cur.users.get_by_id(id = 1).one()
    check r[0] == "1"

    expect QueryError:
      discard cur.users.get_by_id().one()
