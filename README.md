# quma

quma is a small SQL/database library for Nim (target: Nim 2) that maps object-like
method calls to SQL script files.

This repository is a port of:
- Python: `ebenefuenf/quma` (canonical feature set + docs)
- PHP: `duoncode/quma` (PDO-based implementation with similar goals)

The upstream repos are vendored (git-ignored) for reference:
- `data/quma.py`
- `data/quma.php`

## What It Does

- Lets you write plain SQL in files (no ORM) and call them like functions.
- Organizes SQL scripts by folders ("namespaces") and supports root-level
  scripts.
- Supports dynamic SQL via templating (upstream uses Mako in Python; PHP uses
  `*.sql.php` templates).
- Provides a small query wrapper with convenience helpers like `one`, `all`,
  `first`, `exists`, and lazy execution/caching (conceptually).
- Supports multiple database backends: SQLite, PostgreSQL, MySQL/MariaDB.

## Database Backends

quma supports multiple database backends with compile-time selection:

| Backend | URI Scheme | Compile Flag |
|---------|------------|--------------|
| SQLite | `sqlite:///path` or `sqlite:///:memory:` | `-d:qumaSqlite` |
| PostgreSQL | `postgres://user:pass@host:port/db` | `-d:qumaPostgres` |
| MySQL/MariaDB | `mysql://user:pass@host:port/db` or `mariadb://...` | `-d:qumaMysql` |

### Compile-time Backend Selection

By default, all backends are compiled in. To include only specific backends:

```bash
# SQLite only (smaller binary, no libpq dependency)
nim c -d:qumaSqlite myapp.nim

# PostgreSQL only
nim c -d:qumaPostgres myapp.nim

# MySQL only
nim c -d:qumaMysql myapp.nim

# Multiple backends explicitly
nim c -d:qumaSqlite -d:qumaPostgres -d:qumaMysql myapp.nim
```

### Usage Example

```nim
import quma

# SQLite
let sqliteDb = initDatabase("sqlite:///:memory:", store)

# PostgreSQL
let pgDb = initDatabase("postgres://user:pass@localhost:5432/mydb", store)

# MySQL
let mysqlDb = initDatabase("mysql://user:pass@localhost:3306/mydb", store)

# MariaDB
let mariadbDb = initDatabase("mariadb://user:pass@localhost:3306/mydb", store)
```

### Test Database Defaults

The PostgreSQL and MySQL integration tests use `QUMA_`-prefixed environment
variables with defaults so tests can run without extra configuration:

| Backend | Env Vars (defaults) |
|---------|---------------------|
| PostgreSQL | `QUMA_PGSQL_HOST=localhost`, `QUMA_PGSQL_USER=quma`, `QUMA_PGSQL_PASSWORD=quma`, `QUMA_PGSQL_DATABASE=quma`, `QUMA_PGSQL_PORT=5432` |
| MySQL/MariaDB | `QUMA_MYSQL_HOST=127.0.0.1`, `QUMA_MYSQL_USER=quma`, `QUMA_MYSQL_PASSWORD=quma`, `QUMA_MYSQL_DATABASE=quma`, `QUMA_MYSQL_PORT=3306`, `QUMA_MYSQL_SCHEME=mysql` |

Set these variables if your local test database uses different credentials.

### macOS Test RPATHs

On macOS, `tests/config.nims` adds `-Wl,-rpath` entries for Homebrew installs
so `nim r` can load `libpq` and `libmysqlclient` without manual `DYLD_*` setup.
If your libraries live elsewhere, set `DYLD_LIBRARY_PATH` or adjust the paths
in `tests/config.nims`.

## SQL Directory Layout (Upstream Convention)

Given a directory with scripts:

```text
sql/
  users/
    all.sql
    remove.sql
  get_admin.sql
```

The upstream libraries expose these as:
- `cur.users.all()` -> runs `users/all.sql`
- `cur.users.remove(id=...)` -> runs `users/remove.sql`
- `cur.get_admin()` -> runs `get_admin.sql`

Multiple SQL directories can be registered; later/earlier directories can
"shadow" each other to support overrides.

## Dynamic SQL Templates

quma supports dynamic SQL generation using a Svelte-like template syntax. Template
files use the `.nsql` extension, but template syntax is also auto-detected in
regular `.sql` files.

### Syntax

```sql
SELECT * FROM users
WHERE 1=1
{#if filterActive}
  AND active = :active
{/if}
{#if role == 'admin'}
  AND role = 'admin'
{:else if role != ''}
  AND role = :role
{:else}
  AND role IS NOT NULL
{/if}
ORDER BY id
```

### Supported Constructs

| Construct | Description |
|-----------|-------------|
| `{#if expr}...{/if}` | Conditional block |
| `{:else if expr}` | Else-if branch |
| `{:else}` | Else branch |
| `{#include "path"}` | Include another file |

### Expression Language

Template conditions use a simple expression language:

| Type | Literals | Example |
|------|----------|---------|
| string | `'single'` or `"double"` | `name == 'Hans'` |
| int | digits | `count > 10` |
| float | digits with `.` | `price >= 99.99` |
| bool | `true`, `false` | `isActive` |
| null | `null` | `value != null` |

**Operators** (lowest to highest precedence):
- `or` - logical or
- `and` - logical and
- `not` - logical negation
- `==`, `!=` - equality (any type, both sides must match)
- `<`, `<=`, `>`, `>=` - comparison (numeric only)
- `()` - grouping

### Variables

Template variables come from the same named parameters used for SQL binding:

```nim
let q = db.cursor.users.search(filterActive = true, role = "admin")
```

Unknown variables or type mismatches raise `TemplateError` with line/column info.

### Strict Mode

By default, template syntax is auto-detected in both `.sql` and `.nsql` files.
To require explicit `.nsql` extension for templates, enable strict mode:

```nim
let db = initDatabase("sqlite:///app.db", store, strictTemplates = true)
```

In strict mode, template syntax in `.sql` files raises `TemplateError`.

### Includes

Use `{#include "path"}` to insert content from another file:

```sql
-- main.nsql
SELECT * FROM users
{#include "filters/active.inc.sql"}
{#if role == 'admin'}
  {#include "admin/extraFields.nsql"}
{/if}
ORDER BY id
```

#### Include File Extensions

| Extension | Description |
|-----------|-------------|
| `.inc.sql` | Include-only SQL snippet (not callable as script) |
| `.inc.nsql` | Include-only template snippet |
| `.sql`, `.nsql` | Regular scripts (can also be included) |

Files with `.inc.sql` or `.inc.nsql` extensions are excluded from script
discovery, so they cannot be called directly via the cursor API. This lets you
organize reusable SQL fragments without polluting the namespace.

#### Resolution Order

Include paths are resolved in this order:

1. Relative to the current script's directory
2. SQL roots in order (first match wins)

If the path has no extension, quma tries: `.inc.nsql`, `.inc.sql`, `.nsql`, `.sql`

#### Example Structure

```text
sql/
  users/
    all.nsql           # callable as db.cursor.users.all()
    filters.inc.sql    # NOT callable, include-only
  includes/
    pagination.inc.sql # NOT callable (directory has no scripts)
```

#### Cycle Detection

Circular includes are detected at runtime and raise `TemplateError` with the
include chain for debugging.

## Embedded Scripts and Overrides

Downstream applications can embed SQL at compile time and overlay local
filesystem overrides for development.

```nim
import quma

const embedded = embedSqlDir("sql")
let devStore = initFsScriptStore(["sql"])
let store = initOverlayScriptStore(devStore, embedded)
let db = initDatabase("sqlite:///:memory:", store)
```

- `embedSqlDir` expects a path relative to the calling file.
- `initOverlayScriptStore` checks the primary store first, then falls back to
  the embedded scripts.

## Development

- Install dependencies: `atlas install` (do not use Nimble)
- Run tests: `nim test`

## License

MIT (same as upstream).
