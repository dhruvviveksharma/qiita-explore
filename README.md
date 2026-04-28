# qiita-explore

This repository is an extraction of the `ezredbiom` exploratory tooling from
the parent [qiita](https://github.com/qiita-spots/qiita) repository.

## What's here

| Directory | Purpose |
|-----------|---------|
| `ezredbiom/` | The primary package: API server, LLM integration, and biom/redbiom exploration utilities. |
| `qiita_db/` | Vendored verbatim from qiita. Required because `ezredbiom` imports `qiita_db.study` and `qiita_db.sql_connection`. |
| `qiita_core/` | Vendored verbatim from qiita. Transitive dependency of `qiita_db` (`qiita_core.qiita_settings`, `qiita_core.exceptions`). |

## Vendoring strategy

`qiita_db/` and `qiita_core/` are copied here **as-is** to keep the package
importable without requiring a full qiita install. This is a temporary measure
(Strategy A — vendor everything). The planned clean-up is Strategy B: replace
the vendored qiita dependencies with lightweight raw-SQL equivalents, after
which `qiita_db/` and `qiita_core/` can be deleted entirely.

See [REFACTOR_NOTES.md](REFACTOR_NOTES.md) for the full plan.

## License

BSD 3-Clause — see [LICENSE](LICENSE). The vendored `qiita_db/` and
`qiita_core/` code is also covered by the same license from the upstream
qiita project.
