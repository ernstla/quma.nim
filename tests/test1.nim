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
