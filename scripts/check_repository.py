#!/usr/bin/env python3

"""Validate documentation links and reject obvious private capture material."""

from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"\[[^]]*\]\(([^)]+)\)")
FENCED_CODE = re.compile(r"```.*?```|~~~.*?~~~", re.DOTALL)
INLINE_CODE = re.compile(r"`[^`\n]*`")
SECRET_PATTERNS = {
    "GitHub token": re.compile(r"gh[opusr]_[A-Za-z0-9_]{20,}"),
    "AWS access key": re.compile(r"AKIA[0-9A-Z]{16}"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "local user path": re.compile(re.escape("/" + "Users/") + r"[^/\s]+/"),
}


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return [ROOT / line for line in result.stdout.splitlines() if line]


def check_forbidden_paths(files: list[Path]) -> list[str]:
    errors: list[str] = []
    for path in files:
        relative = path.relative_to(ROOT)
        parts = relative.parts
        if path.suffix.lower() == ".har" or any(part.endswith("_extracted") for part in parts):
            errors.append(f"forbidden capture path: {relative}")
        if len(parts) >= 2 and parts[0] == "fixtures" and parts[1] in {"private", "raw"}:
            errors.append(f"forbidden private fixture path: {relative}")
    return errors


def check_text(files: list[Path]) -> list[str]:
    errors: list[str] = []
    text_suffixes = {
        ".dart",
        ".json",
        ".md",
        ".proto",
        ".py",
        ".swift",
        ".ts",
        ".js",
        ".yaml",
        ".yml",
    }
    for path in files:
        if path.suffix.lower() not in text_suffixes:
            continue
        text = path.read_text(encoding="utf-8")
        for name, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                errors.append(f"{path.relative_to(ROOT)}: possible {name}")
        if path.suffix.lower() == ".md":
            prose = INLINE_CODE.sub("", FENCED_CODE.sub("", text))
            for target in LINK.findall(prose):
                if target.startswith(("http://", "https://", "#", "mailto:")):
                    continue
                local_target = target.split("#", 1)[0]
                if local_target and not (path.parent / local_target).resolve().exists():
                    errors.append(f"{path.relative_to(ROOT)}: missing link target {target}")
    return errors


def check_json(files: list[Path]) -> list[str]:
    errors: list[str] = []
    for path in files:
        if path.suffix.lower() != ".json":
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            errors.append(f"{path.relative_to(ROOT)}: invalid JSON: {error}")
    return errors


def main() -> int:
    files = tracked_files()
    errors = check_forbidden_paths(files) + check_text(files) + check_json(files)
    if errors:
        print("Repository validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"Repository validation passed for {len(files)} tracked files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
