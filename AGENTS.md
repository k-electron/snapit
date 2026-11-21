# snapit

## Checks and review

- Before committing, run `scripts/test.sh`: it is the local gate, and CI is only a final check. `scripts/test.sh engine` runs the fast stages, and the pre-commit hook runs them too. README explains every stage, and `docs/testing.md` covers the scripted whole-app run.
- Reviews apply `CODING_STANDARDS.md`: engineering priorities, tests, language and design.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `k-electron/snapit`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.
