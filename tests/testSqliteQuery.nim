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
      discard cur.users.get_by_id(id = 999, name = "Ada").one()

    expect QueryTooManyRowsError:
      discard cur.users.all().one()

  test "named param compilation to positional binds":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text);")
    cur.exec("insert into users(id, name) values (1, 'Ada');")

    cur.exec("insert into users(id, name) values (2, 'Bob');")

    let r = cur.users.get_by_id(id = 1, name = "Ada", extra = "ignore").one()
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

    let missing = cur.users.get_by_id(id = 999, name = "Ada").first()
    check missing.isNone

  test "template rendering with conditionals":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text, active int);")
    cur.exec("insert into users(id, name, active) values (1, 'Ada', 1);")
    cur.exec("insert into users(id, name, active) values (2, 'Bob', 0);")
    cur.exec("insert into users(id, name, active) values (3, 'Ada', 0);")

    # No filters - get all 3
    let all = cur.users.search(filterActive = false, filterName = false).all()
    check all.len == 3

    # Filter by active only
    let activeOnly =
      cur.users.search(filterActive = true, active = 1, filterName = false).all()
    check activeOnly.len == 1
    check activeOnly[0][1] == "Ada"

    # Filter by name only
    let namedAda =
      cur.users.search(filterActive = false, filterName = true, name = "Ada").all()
    check namedAda.len == 2

    # Filter by both
    let activeAda = cur.users
      .search(filterActive = true, active = 1, filterName = true, name = "Ada")
      .all()
    check activeAda.len == 1
    check activeAda[0][0] == "1" # id = 1
