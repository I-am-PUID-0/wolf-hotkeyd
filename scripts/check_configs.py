from __future__ import annotations

from pathlib import Path

from wolf_hotkeyd.config import load_config


def main() -> int:
    for path in sorted(Path("examples").glob("*.yaml")):
        load_config(path, allow_missing=False)
        print(f"loaded {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
