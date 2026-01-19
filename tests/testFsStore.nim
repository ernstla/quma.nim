import std/[os, strutils, tempfiles]
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

  test "cache stores resolved scripts by default":
    let base = joinPath(getCurrentDir(), "tests/fixtures/sql/base")
    let store = initFsScriptStore([base])

    discard store.getScript("users/all")
    check cacheEnabled(store)

  test "reload bypasses cache":
    let tempDir = createTempDir("quma_reload_", "")
    let sqlDir = joinPath(tempDir, "sql")
    createDir(sqlDir)
    let scriptPath = joinPath(sqlDir, "greeting.sql")
    writeFile(scriptPath, "select 1;\n")

    let store = initFsScriptStore([sqlDir], reload = true)
    check store.getScript("greeting").sql.contains("select 1")

    writeFile(scriptPath, "select 2;\n")
    check store.getScript("greeting").sql.contains("select 2")

  test "cache can be disabled":
    let base = joinPath(getCurrentDir(), "tests/fixtures/sql/base")
    let store = initFsScriptStore([base], cache = false)

    discard store.getScript("users/all")
    check cacheEnabled(store) == false

  test "clearCache reloads scripts":
    let tempDir = createTempDir("quma_cache_", "")
    let sqlDir = joinPath(tempDir, "sql")
    createDir(sqlDir)
    let scriptPath = joinPath(sqlDir, "greeting.sql")
    writeFile(scriptPath, "select 1;\n")

    let store = initFsScriptStore([sqlDir])
    check store.getScript("greeting").sql.contains("select 1")

    writeFile(scriptPath, "select 2;\n")
    check store.getScript("greeting").sql.contains("select 1")

    clearCache(store)
    check store.getScript("greeting").sql.contains("select 2")

  test "resolveInclude finds include files":
    let tempDir = createTempDir("quma_inc_", "")
    let sqlDir = joinPath(tempDir, "sql")
    createDir(sqlDir)

    # Create include files
    writeFile(joinPath(sqlDir, "header.inc.sql"), "-- Header\n")
    writeFile(joinPath(sqlDir, "footer.inc.nsql"), "-- Footer\n")
    writeFile(joinPath(sqlDir, "shared.sql"), "SELECT shared\n")

    let store = initFsScriptStore([sqlDir])

    # Direct include with extension
    check store.resolveInclude("header.inc.sql", sqlDir).contains("Header")
    check store.resolveInclude("footer.inc.nsql", sqlDir).contains("Footer")
    check store.resolveInclude("shared.sql", sqlDir).contains("shared")

    # Include without extension tries in order
    check store.resolveInclude("header", sqlDir).contains("Header")
    check store.resolveInclude("footer", sqlDir).contains("Footer")
    check store.resolveInclude("shared", sqlDir).contains("shared")

  test "resolveInclude relative to current script dir":
    let tempDir = createTempDir("quma_inc_rel_", "")
    let sqlDir = joinPath(tempDir, "sql")
    let subDir = joinPath(sqlDir, "queries")
    createDir(sqlDir)
    createDir(subDir)

    # Include in subdir
    writeFile(joinPath(subDir, "local.inc.sql"), "-- Local\n")

    let store = initFsScriptStore([sqlDir])

    # Resolve from subdir
    check store.resolveInclude("local.inc.sql", subDir).contains("Local")

    # Not found from root
    expect ScriptNotFoundError:
      discard store.resolveInclude("local.inc.sql", sqlDir)

  test "resolveInclude last added wins":
    let tempDir = createTempDir("quma_inc_shadow_", "")
    let baseDir = joinPath(tempDir, "base")
    let overrideDir = joinPath(tempDir, "override")
    createDir(baseDir)
    createDir(overrideDir)

    writeFile(joinPath(baseDir, "common.inc.sql"), "-- Base\n")
    writeFile(joinPath(overrideDir, "common.inc.sql"), "-- Override\n")

    # First dir wins (last added should come first in the list)
    let store = initFsScriptStore([overrideDir, baseDir])
    let content = store.resolveInclude("common.inc.sql", tempDir)
    check content.contains("Override")
    check not content.contains("Base")
