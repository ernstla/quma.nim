import std/[options, os]
import unittest

import quma

type UserId = object
  id: int

type UserProfile = object
  id {.qumaColumn: "user_id".}: int
  name: string

suite "SQLite Query":
  test "can execute script and fetch helpers":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])

    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text);")
    cur.exec("insert into users(id, name) values (1, 'Ada');")
    cur.exec("insert into users(id, name) values (2, 'Bob');")

    expect QueryNoRowsError:
      discard cur.users.get_by_id(id = 999).one()

    expect QueryTooManyRowsError:
      discard cur.users.all().one()

  test "named param compilation to positional binds":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text);")
    cur.exec("insert into users(id, name) values (1, 'Ada');")

    let r = cur.users.get_by_id(id = 1).one()
    check r[0] == "1"

    expect QueryError:
      discard cur.users.get_by_id().one()

  test "typed query mapping":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text);")
    cur.exec("insert into users(id, name) values (1, 'Ada');")
    cur.exec("insert into users(id, name) values (2, 'Bob');")

    let ids = cur.users.all[UserId]().all()
    check ids.len == 2
    check ids[0].id == 1

    let profile = cur.users.all_profiles[UserProfile]().first()
    check profile.isSome
    check profile.get.id == 1
    check profile.get.name == "Ada"

    let missing = cur.users.get_by_id(id = 999).first()
    check missing.isNone
