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
- Supports multiple databases upstream: SQLite, PostgreSQL, MySQL/MariaDB.

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
