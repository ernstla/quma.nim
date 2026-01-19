switch("path", "$projectDir/../src")

# Default to SQLite-only for tests (unless postgres or mysql tests are enabled)
when not defined(qumaPostgres) and not defined(qumaMysql):
  switch("define", "qumaSqlite")
