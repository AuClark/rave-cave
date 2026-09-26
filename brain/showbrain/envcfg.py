"""Tiny .env loader and ${VAR:-default} expansion, so site-specific values stay out of git.

Values come from the process environment first, then from `.env` files (first found wins):
next to this module, then the repo root. `.env` is git-ignored; see `.env.example`.
"""
import os
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
_VAR = re.compile(r"\$\{([A-Z0-9_]+)(?::-([^}]*))?\}")


def load_env(*extra):
    """Read KEY=VALUE lines from .env files into os.environ (existing variables win)."""
    root = next((q for q in HERE.parents if (q / ".env.example").exists()), None)
    for p in [*extra, HERE / ".env", *( [root / ".env"] if root else [] )]:
        p = Path(p)
        if not p.is_file():
            continue
        for line in p.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def expand(text):
    """Replace ${VAR} / ${VAR:-default} with environment values."""
    return _VAR.sub(lambda m: os.environ.get(m.group(1), m.group(2) or ""), text)
