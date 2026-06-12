#!/usr/bin/env python3
"""Fail the build when xccov JSON coverage drops below a threshold."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coverage_json", type=Path)
    parser.add_argument("--threshold", type=float, default=90.0)
    parser.add_argument(
        "--ignore",
        action="append",
        default=[],
        help="Path suffix to exclude from coverage math. Can be passed multiple times.",
    )
    parser.add_argument("--target", default="PatternAuthentication")
    return parser.parse_args()


def ignored(path: str, ignored_suffixes: list[str]) -> bool:
    normalized = path.replace("\\", "/")
    return any(normalized.endswith(suffix) for suffix in ignored_suffixes)


def main() -> int:
    args = parse_args()
    report = json.loads(args.coverage_json.read_text())
    target = next(
        (item for item in report["targets"] if item.get("name") == args.target),
        None,
    )
    if target is None:
        raise SystemExit(f"Coverage target {args.target!r} not found.")

    covered = 0
    executable = 0
    included_files: list[tuple[str, int, int]] = []

    for file_report in target["files"]:
        path = file_report["path"]
        if ignored(path, args.ignore):
            continue
        file_covered = int(file_report["coveredLines"])
        file_executable = int(file_report["executableLines"])
        covered += file_covered
        executable += file_executable
        included_files.append((path, file_covered, file_executable))

    if executable == 0:
        raise SystemExit("Coverage report contained no executable lines.")

    coverage = (covered / executable) * 100
    print(f"Coverage for {args.target}: {coverage:.2f}% ({covered}/{executable})")
    for path, file_covered, file_executable in included_files:
        file_coverage = (file_covered / file_executable) * 100 if file_executable else 100
        print(f"  {file_coverage:6.2f}%  {file_covered:4}/{file_executable:<4} {path}")

    if coverage < args.threshold:
        print(f"Coverage is below required threshold: {coverage:.2f}% < {args.threshold:.2f}%")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
