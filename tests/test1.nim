import std/tables
import unittest

import quma

suite "quma":
  test "can construct Database and Cursor":
    let db = initDatabase("sqlite:///:memory:")
    check db != nil

    let cur = db.cursor()
    check cur != nil

  test "can construct Query":
    let db = initDatabase("sqlite:///:memory:")
    let cur = db.cursor()
    let q = initQuery(cur, "users/all", initScriptArgs())
    check q != nil

  test "dotOperators builds namespace + script refs":
    let db = initDatabase("sqlite:///:memory:")
    let cur = db.cursor()

    let ns = cur.users
    check ns.segments == @["users"]

    let sr = cur.users.all
    check sr.segments == @["users", "all"]
    check sr.scriptId() == "users/all"

    let q = cur.users.all()
    check q.scriptId() == "users/all"

  test "script call captures positional and named args":
    let db = initDatabase("sqlite:///:memory:")
    let cur = db.cursor()

    let q = cur.users.all(1, name = "bob", active = true)
    let a = q.scriptArgs()

    check a.positional.len == 1
    check a.positional[0].kind == avkInt
    check a.positional[0].i == 1

    check a.named["name"].kind == avkString
    check a.named["name"].s == "bob"

    check a.named["active"].kind == avkBool
    check a.named["active"].b == true
