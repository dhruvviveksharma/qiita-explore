# Refactor Notes

## Current state: Strategy A — Vendor everything

`qiita_db/` and `qiita_core/` are vendored verbatim from the upstream qiita
repository. This was chosen for speed: it gets `ezredbiom` importable and
runnable with zero code changes. It is explicitly a **temporary** arrangement.

## Target state: Strategy B — Replace vendored deps with raw SQL

The goal is to eliminate the vendored directories entirely by:

1. **Replacing `qiita_db.sql_connection.TRN` usage** with a thin psycopg2
   wrapper (a small `db.py` or similar inside `ezredbiom/`) that opens a
   connection from an environment variable and executes SQL directly.

2. **Replacing `qiita_db.study.Study` / `StudyPerson` reads** with raw SQL
   queries, leveraging the SQL files already present in
   `ezredbiom/sql_scripts/` (e.g. `study.sql`, `sample_metadata.sql`, etc.).

Once those two substitutions are done, `qiita_db/` and `qiita_core/` can be
deleted and removed from `requirements.txt`.

## Concrete touchpoints to refactor

The following files in `ezredbiom/` currently import from `qiita_db.*` and
will need to be updated:

| File | What it imports |
|------|----------------|
| `ezredbiom/api_server.py` | `qiita_db.sql_connection.TRN` and/or `qiita_db.study.*` |
| `ezredbiom/qiita.py` | `qiita_db.study.Study`, `StudyPerson` |
| `ezredbiom/LLM.py` | `qiita_db.sql_connection.TRN` |
| `ezredbiom/Works/new_api.py` | `qiita_db.sql_connection.TRN` |
| `ezredbiom/Experiment/backend/run.py` | `qiita_db.sql_connection.TRN` |
| `ezredbiom/Experiment/backend/services/study_service.py` | `qiita_db.study.Study`, `StudyPerson` |

## Leveraging existing SQL scripts

`ezredbiom/sql_scripts/` already contains raw SQL counterparts for the
qiita_db ORM queries:

- `study.sql` — study metadata lookups
- `sample_metadata.sql` — per-sample metadata
- (plus others in the same directory)

The refactor should wire these scripts through the new thin psycopg2 wrapper
rather than reimplementing the queries from scratch.

## Why this matters

Eliminating the vendored qiita stack will:
- Shrink the dependency surface dramatically (no more qiita-files wheel, no
  `-e git+...` qiita editable install, etc.)
- Make the package independently pip-installable
- Remove the risk of qiita upstream changes silently breaking this repo
