#!/usr/bin/env python3

"""Validate JSON Schemas and shared positive/negative conformance fixtures."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "fixtures/conformance/manifest.json"


def load_json(relative_path: str) -> object:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    failures: list[str] = []

    for case in manifest["cases"]:
        schema = load_json(case["schema"])
        fixture = load_json(case["fixture"])
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        errors = sorted(validator.iter_errors(fixture), key=lambda error: list(error.path))
        actual_valid = not errors
        if actual_valid != case["valid"]:
            detail = "valid" if actual_valid else errors[0].message
            failures.append(f'{case["name"]}: expected valid={case["valid"]}, got {detail}')

    if failures:
        print("Contract validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f'Contract validation passed for {len(manifest["cases"])} fixtures.')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
