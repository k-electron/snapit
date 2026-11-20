# snapit

## Engineering priorities

Rank every trade-off: **correctness**, then **safety**, then **stability**, then **performance**. Performance matters and ranks fourth.

snapit stays small, light and fast through ordinary good engineering. Features and UX are built in full and are never shaped to fit a performance number. For each resource the app uses (CPU, memory, GPU, disk, file handles, anything else), ask:

1. **Justified:** does the feature set need it?
2. **Proportionate:** does what snapit's own process holds add up to what the running feature requires?
3. **Released:** does it return to the process's own baseline when the flow ends?
4. **Well chosen:** is the algorithm the best on correctness, then safety, then stability, then performance?

Resource review is a reading of the code against these four questions. Tests cover behaviour and release (clean-up after each flow), measured against the process's own baseline and the feature's own size, with generous margins, and pass the same way on every machine.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `k-electron/snapit`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.
