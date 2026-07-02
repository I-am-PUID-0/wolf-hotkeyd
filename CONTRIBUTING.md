# Contributing to wolf-hotkeyd

Thanks for contributing to wolf-hotkeyd.

## Branch Model

- `main` is the production and release branch.
- Open normal feature and bugfix pull requests against `main` unless a
  maintainer directs otherwise.
- Release Please uses Conventional Commits on `main` to prepare releases.

## Basic Workflow

1. Fork the repository.
2. Create a focused feature or bugfix branch.
3. Make the smallest coherent change that solves the issue.
4. Update relevant docs when behavior, setup, security, or operations change.
5. Run verification before opening a pull request.
6. Open the pull request with a conventional title.

## Commit Style

wolf-hotkeyd uses [Conventional Commits](https://www.conventionalcommits.org/).
PR titles and commits are validated automatically.

Allowed types: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`,
`test`, `build`, `ci`, `revert`, `breaking`.

Examples:

```text
feat: add host-side hotkey action mode
fix: avoid selecting crash reporter helper processes
docs: document anti-cheat-safe runner choices
```

## Local Checks

Install the project in a virtual environment:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e .
```

Run the lightweight verification commands:

```bash
make bootstrap
make verify
```

That target checks text/EOF whitespace for tracked and untracked files,
checks Ruff linting/formatting, compiles the Python package, loads every
example config, runs unit tests, and validates shell script syntax.

To auto-format before a commit:

```bash
make format
```

If Docker is available and you changed the Steam runner image scaffold, also
build it locally:

```bash
docker build -f deploy/steam-hotkeyd-image/Dockerfile -t wolf-steam-hotkeyd:dev .
```

## Pull Request Expectations

- Use Conventional Commit style for PR titles and commits.
- Include a concise summary and testing notes.
- Link related issues when applicable.
- Update docs or explicitly explain why docs were not needed.
- Keep unrelated refactors out of feature and bugfix PRs.
- Do not commit local hostnames, domains, tokens, paths, capture logs, Steam
  account details, container IDs, or other deployment-specific identifiers.

## Anti-Cheat And Safety

wolf-hotkeyd can read Linux input devices and inspect process lists depending
on the selected mode and action script. Some anti-cheat systems may classify
that behavior as suspicious. Changes that affect input listening, process
selection, or container execution should document the operational risk and keep
anti-cheat-protected game modes opt-in or easy to disable.
