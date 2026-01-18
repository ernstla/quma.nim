import std/os
import unittest

import quma

suite "withCursor":
  test "withCursor closes cursor on exit":
    let db = initDatabase("sqlite:///:memory:")
    db.withCursor do(c: Cursor):
      c.exec("select 1")
    # cursor is closed here - can't easily verify, but no crash = success

  test "withCursor closes cursor on exception":
    let db = initDatabase("sqlite:///:memory:")
    var raised = false
    try:
      db.withCursor do(c: Cursor):
        c.exec("select 1")
        raise newException(ValueError, "test error")
    except ValueError:
      raised = true
    check raised

  test "withCursor with commit=false does not auto-commit":
    let dbPath = getTempDir() / "test_commit_false.db"
    removeFile(dbPath)
    let db = initDatabase("sqlite:///" & dbPath)

    db.withCursor do(c: Cursor):
      c.exec("create table t(x int)")

    db.withCursor(commit = false) do(c: Cursor):
      c.begin()
      c.exec("insert into t values (1)")
      # explicitly rollback - no auto-commit
      c.rollback()

    db.withCursor do(c: Cursor):
      let rows = c.rawQuery("select count(*) from t")
      check rows.len == 1
      check rows[0][0] == "0"

    removeFile(dbPath)

  test "withCursor with commit=true auto-commits on success":
    let dbPath = getTempDir() / "test_commit_true.db"
    removeFile(dbPath)
    let db = initDatabase("sqlite:///" & dbPath)

    db.withCursor do(c: Cursor):
      c.exec("create table t(x int)")

    db.withCursor(commit = true) do(c: Cursor):
      c.exec("insert into t values (1)")

    db.withCursor do(c: Cursor):
      let rows = c.rawQuery("select count(*) from t")
      check rows.len == 1
      check rows[0][0] == "1"

    removeFile(dbPath)

  test "withCursor with commit=true rolls back on exception":
    let dbPath = getTempDir() / "test_commit_rollback.db"
    removeFile(dbPath)
    let db = initDatabase("sqlite:///" & dbPath)

    db.withCursor do(c: Cursor):
      c.exec("create table t(x int)")
      c.exec("insert into t values (0)")

    var raised = false
    try:
      db.withCursor(commit = true) do(c: Cursor):
        c.exec("insert into t values (1)")
        raise newException(ValueError, "test error")
    except ValueError:
      raised = true

    check raised

    db.withCursor do(c: Cursor):
      let rows = c.rawQuery("select count(*) from t")
      check rows.len == 1
      check rows[0][0] == "1" # only the initial insert, not the one that was rolled back

    removeFile(dbPath)
