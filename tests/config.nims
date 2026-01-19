import std/os

switch("path", "$projectDir/../src")

# Default to SQLite-only for tests (unless postgres or mysql tests are enabled)
when not defined(qumaPostgres) and not defined(qumaMysql):
  switch("define", "qumaSqlite")

when defined(macosx):
  when defined(arm64):
    const libpqPath = "/opt/homebrew/opt/libpq/lib"
    const mysqlPath = "/opt/homebrew/opt/mysql-client/lib"
  else:
    const libpqPath = "/usr/local/opt/libpq/lib"
    const mysqlPath = "/usr/local/opt/mysql-client/lib"

  if dirExists(libpqPath):
    switch("passL", "-Wl,-rpath," & libpqPath)
  if dirExists(mysqlPath):
    switch("passL", "-Wl,-rpath," & mysqlPath)
