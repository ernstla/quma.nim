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
      discard cur.users.getById(id = 999, name = "Ada").one()

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

    let r = cur.users.getById(id = 1, name = "Ada", extra = "ignore").one()
    check r[0] == "1"

    expect QueryError:
      discard cur.users.getById().one()

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

    let profile = cur.users.allProfiles[UserProfile]().first()
    check profile.isSome
    check profile.get.id == 1
    check profile.get.name == "Ada"

    let missing = cur.users.getById(id = 999, name = "Ada").first()
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

  test "auto-detect template syntax in .sql files":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text, active int);")
    cur.exec("insert into users(id, name, active) values (1, 'Ada', 1);")
    cur.exec("insert into users(id, name, active) values (2, 'Bob', 0);")

    # Uses searchAutodetect.sql which has template syntax in a .sql file
    let all = cur.users.searchAutodetect(filterActive = false).all()
    check all.len == 2

    let activeOnly = cur.users.searchAutodetect(filterActive = true, active = 1).all()
    check activeOnly.len == 1

  test "strictTemplates rejects template syntax in .sql files":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store, strictTemplates = true)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text, active int);")

    # Should raise TemplateError because searchAutodetect.sql has template syntax
    expect TemplateError:
      discard cur.users.searchAutodetect(filterActive = false).all()

  test "strictTemplates allows .nsql files":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store, strictTemplates = true)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text, active int);")
    cur.exec("insert into users(id, name, active) values (1, 'Ada', 1);")

    # search.nsql should work fine even in strict mode
    let results =
      cur.users.search(filterActive = true, active = 1, filterName = false).all()
    check results.len == 1

  test "include simple SQL fragment":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text, active int);")
    cur.exec("insert into users(id, name, active) values (1, 'Ada', 1);")
    cur.exec("insert into users(id, name, active) values (2, 'Bob', 0);")

    # searchWithSimpleInclude.nsql includes filters.inc.sql which adds "AND active = 1"
    let results = cur.users.searchWithSimpleInclude().all()
    check results.len == 1
    check results[0][1] == "Ada"

  test "include template with conditionals":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text, active int);")
    cur.exec("insert into users(id, name, active) values (1, 'Ada', 1);")
    cur.exec("insert into users(id, name, active) values (2, 'Bob', 0);")
    cur.exec("insert into users(id, name, active) values (3, 'Ada', 0);")

    # searchWithInclude.nsql includes activeFilter.inc.nsql which has {#if filterActive}
    # No filter - get all 3
    let all =
      cur.users.searchWithInclude(filterActive = false, filterName = false).all()
    check all.len == 3

    # Filter by active via included template
    let activeOnly = cur.users
      .searchWithInclude(filterActive = true, active = 1, filterName = false)
      .all()
    check activeOnly.len == 1
    check activeOnly[0][1] == "Ada"

    # Filter by both (active from include, name from main template)
    let activeAda = cur.users
      .searchWithInclude(
        filterActive = true, active = 1, filterName = true, name = "Ada"
      )
      .all()
    check activeAda.len == 1

  test "conditional include":
    let sqlDir = joinPath(getCurrentDir(), "tests/fixtures/sql/sqlite")
    let store = initFsScriptStore([sqlDir])
    let db = initDatabase("sqlite:///:memory:", store)
    let cur = db.cursor()

    cur.exec("create table users(id int, name text, active int);")
    cur.exec("insert into users(id, name, active) values (1, 'Ada', 1);")
    cur.exec("insert into users(id, name, active) values (2, 'Bob', 0);")

    # searchConditionalInclude.nsql: {#if useActiveFilter}{#include "filters.inc.sql"}{/if}
    # Without the filter - get all 2
    let all = cur.users.searchConditionalInclude(useActiveFilter = false).all()
    check all.len == 2

    # With the filter - include is processed, adds "AND active = 1"
    let activeOnly = cur.users.searchConditionalInclude(useActiveFilter = true).all()
    check activeOnly.len == 1
    check activeOnly[0][1] == "Ada"
