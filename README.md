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
