# AGENTS.md — partitia

The Rails engines CNFS apps are built from: support, dev, telemetry, tenanted, iam, cognito, ui.
One gem per directory (`<dir>/partitia-<dir>.gemspec`, module `Partitia::<Name>`).

Read first:

- `ROADMAP.md` — where this is going, the decisions already made, and per destination what an
  agent needs to know.
- `ARCHITECTURE.md` — the layers and the engine contract every engine meets; `DIAGRAMS.md` pictures them.
- `<gem>/AGENTS.md` where a gem has one, then its `README.md` and `progress.md`.
- ADRs: the docs repo beside this one (`../doc/adrs`); `../doc/archive/` is history, not
  maintained.

Working here:

- Each gem stands alone: `cd <gem> && bundle exec rspec`, `bin/rubocop`. Siblings resolve
  through Gemfile `path:` entries; from elsewhere through gem-local.
- Apps and engines are made and run with `cnfs`: `cnfs new`, `cnfs server`, `cnfs engine new`.
- Commit to main; the person reviews and pushes.
