switch("path", "$projectDir/../src")

# Default to SQLite-only for tests (unless postgres tests are explicitly enabled)
when not defined(qumaPostgres):
  switch("define", "qumaSqlite")
