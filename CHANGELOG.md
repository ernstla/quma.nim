# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- PostgreSQL backend support (`postgres://` URIs)
- MySQL/MariaDB backend support (`mysql://`, `mariadb://` URIs)
- Backend abstraction layer for multi-database support
- Compile-time backend selection flags (`-d:qumaSqlite`, `-d:qumaPostgres`, `-d:qumaMysql`)
- Template include system (`{#include "path"}`) for reusable SQL fragments
- Include-only file extensions (`.inc.sql`, `.inc.nsql`)
- Cycle detection for circular includes
- `strictTemplates` mode to require explicit `.nsql` extension
