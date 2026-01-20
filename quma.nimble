# Package

version       = "0.1.0"
author        = "Thomas Ernst"
description   = "A database & SQL library"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.2.0"
requires "db_connector"


import std/[os, strutils]

proc formatTestArgs(): string =
  let envArgs = getEnv("QUMA_TEST_BACKENDS", "").strip()
  if envArgs.len > 0:
    return " " & envArgs
  ""

task test, "Run test suite":
  exec "nim test" & formatTestArgs()
