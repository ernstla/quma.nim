import std/[os, strutils]
import unittest

import quma

suite "Embedded Script Stores":
  test "embedSqlDir loads scripts and namespaces":
    let store = embedSqlDir("fixtures/sql/embedded")

    check store.hasNamespace("users")
    check store.hasNamespace("users/admin")
    check store.hasNamespace("missing") == false

    let rootScript = store.getScript("all")
    check rootScript.sql.contains("select 99")
    check rootScript.origin.endsWith("tests/fixtures/sql/embedded/all.sql")

    let nested = store.getScript("users/all")
    check nested.sql.contains("select 10")

  test "overlay uses primary scripts when available":
    let embedded = embedSqlDir("fixtures/sql/embedded")
    let overlayDir = joinPath(getCurrentDir(), "tests/fixtures/sql/overlay")
    let overlayStore = initFsScriptStore([overlayDir])
    let store = initOverlayScriptStore(overlayStore, embedded)

    let overridden = store.getScript("users/all")
    check overridden.origin.endsWith("tests/fixtures/sql/overlay/users/all.sql")
    check overridden.sql.contains("select 42")

    let fallback = store.getScript("users/admin/list")
    check fallback.origin.endsWith("tests/fixtures/sql/embedded/users/admin/list.sql")

    let primaryOnly = store.getScript("only")
    check primaryOnly.origin.endsWith("tests/fixtures/sql/overlay/only.sql")

  test "embedSqlDir excludes include files from discovery":
    let store = embedSqlDir("fixtures/sql/embedded")

    # Include files should not be discoverable as scripts
    expect ScriptNotFoundError:
      discard store.getScript("common.inc")

    expect ScriptNotFoundError:
      discard store.getScript("filter.inc")

    expect ScriptNotFoundError:
      discard store.getScript("common")

    # Regular scripts should still work
    check store.getScript("all").sql.contains("select 99")
