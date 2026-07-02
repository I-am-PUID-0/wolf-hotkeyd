from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "__pycache__",
    "build",
    "dist",
}
SKIP_SUFFIXES = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".ico",
    ".pyc",
    ".so",
    ".tar",
    ".gz",
    ".zip",
}


def main() -> int:
    errors: list[str] = []
    for path in _candidate_files():
        rel = path.relative_to(ROOT)
        try:
            data = path.read_bytes()
        except OSError as exc:
            errors.append(f"{rel}: unable to read: {exc}")
            continue

        if b"\0" in data:
            continue

        text = data.decode("utf-8", errors="replace")
        lines = text.splitlines(keepends=True)
        for index, line in enumerate(lines, start=1):
            body = line[:-1] if line.endswith("\n") else line
            if body.endswith((" ", "\t")):
                errors.append(f"{rel}:{index}: trailing whitespace")

        if data and not data.endswith(b"\n"):
            errors.append(f"{rel}: missing newline at EOF")
        if data.endswith(b"\n\n"):
            errors.append(f"{rel}: new blank line at EOF")

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print("text checks passed")
    return 0


def _candidate_files() -> list[Path]:
    tracked = _git_paths(["git", "ls-files", "-z"])
    untracked = _git_paths(["git", "ls-files", "--others", "--exclude-standard", "-z"])
    paths = sorted({*tracked, *untracked})
    return [path for path in paths if _should_check(path)]


def _git_paths(command: list[str]) -> list[Path]:
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [ROOT / item.decode("utf-8") for item in result.stdout.split(b"\0") if item]


def _should_check(path: Path) -> bool:
    rel_parts = path.relative_to(ROOT).parts
    if any(part in SKIP_DIRS for part in rel_parts):
        return False
    if path.suffix.lower() in SKIP_SUFFIXES:
        return False
    return path.is_file()


if __name__ == "__main__":
    raise SystemExit(main())
