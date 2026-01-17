import std/[os, strutils]
import unittest

import quma

suite "FsScriptStore":
  test "hasNamespace finds folders across dirs":
    let base = joinPath(getCurrentDir(), "tests/fixtures/sql/base")
    let override = joinPath(getCurrentDir(), "tests/fixtures/sql/override")

    let store = initFsScriptStore([override, base])

    check store.hasNamespace("users")
    check store.hasNamespace("users/admin")
    check store.hasNamespace("missing") == false

  test "getScript resolves shadowing last added wins":
    let base = joinPath(getCurrentDir(), "tests/fixtures/sql/base")
    let override = joinPath(getCurrentDir(), "tests/fixtures/sql/override")

    let store = initFsScriptStore([override, base])

    let usersAll = store.getScript("users/all")
    check usersAll.origin.endsWith("tests/fixtures/sql/override/users/all.sql")
    check usersAll.sql.contains("select 2")

    let adminList = store.getScript("users/admin/list")
    check adminList.origin.endsWith("tests/fixtures/sql/base/users/admin/list.sql")
    check adminList.sql.contains("base")

  test "getScript errors on missing script":
    let base = joinPath(getCurrentDir(), "tests/fixtures/sql/base")
    let store = initFsScriptStore([base])

    expect ScriptNotFoundError:
      discard store.getScript("does/not/exist")
