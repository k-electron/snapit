# Contributing to snapit

snapit is built with [Matt Pocock's skills](https://github.com/mattpocock/skills), and the repo is already set up for them. This page is the flow, in the order work moves.

## The flow

1. **Open an issue.** A bug or a request starts as an issue, using the bug report or feature request template. A pull request is not a way to request a feature: a change nobody asked for in an issue may not be merged, so the issue comes first.
2. **Triage.** The maintainer runs [`/triage`](https://github.com/mattpocock/skills/blob/main/skills/engineering/triage/SKILL.md) over unlabelled issues. It moves each one to `ready-for-agent` or `ready-for-human`, or asks the reporter for more information. **Anyone may take an issue labelled `ready-for-agent` or `ready-for-human`.** Say so in a comment on the issue before you start.
3. **Bigger ideas.** An idea too big for one issue goes through [`/grill-with-docs`](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md) (stress-test the plan against the glossary), [`/to-spec`](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-spec/SKILL.md) (write the spec as an issue) and [`/to-tickets`](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md) (split it into tickets).
4. **Build.** [`/implement`](https://github.com/mattpocock/skills/blob/main/skills/engineering/implement/SKILL.md) builds one ticket, driving [`/tdd`](https://github.com/mattpocock/skills/blob/main/skills/engineering/tdd/SKILL.md) and [`/code-review`](https://github.com/mattpocock/skills/blob/main/skills/engineering/code-review/SKILL.md). [`/implement-spec`](https://github.com/mattpocock/skills/blob/main/skills/engineering/implement-spec/SKILL.md) builds a whole spec.
5. **Open the pull request.** Write its body with the [`/pr`](https://github.com/mattpocock/skills/blob/main/skills/engineering/pr/SKILL.md) skill: it gives the Summary, the Evidence and the Merge Danger the maintainer reads.
6. **Close the loop.** [`/retro`](https://github.com/mattpocock/skills/blob/main/skills/engineering/retro/SKILL.md) looks back at the work and feeds what it learned into the next round.

The skills come from the [Matt Pocock skills repo](https://github.com/mattpocock/skills), where [`/setup-matt-pocock-skills`](https://github.com/mattpocock/skills/blob/main/skills/engineering/setup-matt-pocock-skills/SKILL.md) installs them. You do not run its setup in this repo.

## The repo's skill config

The setup is already done. The skills read it from these files:

- [Issue tracker](docs/agents/issue-tracker.md): issues and specs live in GitHub Issues, managed with the `gh` CLI.
- [Triage labels](docs/agents/triage-labels.md): `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human` and `wontfix`.
- [Domain docs](docs/agents/domain.md): one glossary and `docs/adr/` at the repo root.

## The words and the rules

- [GLOSSARY.md](GLOSSARY.md) holds snapit's terms (Capture, Area, Editor, Annotation, Export, and so on). Docs, UI copy, code and comments use them.
- [CODING_STANDARDS.md](CODING_STANDARDS.md) holds the rules a review applies. `/code-review` reads both files as its standards, so they are linked here and not repeated.

## The local gate

- Run the full `scripts/test.sh` before you push. CI is only a final check.
- Enable the pre-commit hook once after cloning: `git config core.hooksPath .githooks`. It runs `scripts/test.sh engine`, the fast stages, before each commit.

[Testing](docs/development/testing.md) explains every stage.

## Keeping the docs true

- A change in behaviour updates the [User Guide](docs/UserGuide.md) in the same pull request.
- A visible UI change updates the affected shots in the [shot list](docs/development/shot-list.md).

## Where to start reading

The [technical index](docs/development/index.md) links the architecture, building, testing, releasing and manual-check docs, the shot list and the specs.
