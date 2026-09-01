#!/usr/bin/env python3

import argparse
import json
import math
import re
import statistics
from collections import defaultdict
from pathlib import Path


SAMPLE_PATTERN = re.compile(
    r"metric=(?P<metric>\S+) "
    r"elapsed_ms=(?P<elapsed>[0-9]+(?:\.[0-9]+)?) "
    r"rating=(?P<rating>\S+) "
    r"outcome=(?P<outcome>\S+)"
)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(len(ordered) * fraction) - 1)
    return ordered[index]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Summarize CineLark privacy-safe performance log samples."
    )
    parser.add_argument("capture", type=Path, help="NDJSON file emitted by log stream")
    arguments = parser.parse_args()

    samples: dict[str, list[tuple[float, str, str]]] = defaultdict(list)
    with arguments.capture.open(encoding="utf-8") as capture:
        for line in capture:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = event.get("eventMessage", "")
            match = SAMPLE_PATTERN.search(message)
            if match is None:
                continue
            samples[match.group("metric")].append(
                (
                    float(match.group("elapsed")),
                    match.group("rating"),
                    match.group("outcome"),
                )
            )

    if not samples:
        print("No CineLark performance samples found.")
        return 1

    print("| Metric | Count | Success | Success median (ms) | Success P95 (ms) | Success max (ms) | Above target | Critical | Fail/Cancel |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for metric in sorted(samples):
        metric_samples = samples[metric]
        successful_elapsed = [
            sample[0] for sample in metric_samples if sample[2] == "success"
        ]
        above_target = sum(sample[1] == "exceededTarget" for sample in metric_samples)
        critical = sum(sample[1] == "exceededCritical" for sample in metric_samples)
        incomplete = sum(sample[2] != "success" for sample in metric_samples)
        if successful_elapsed:
            median = f"{statistics.median(successful_elapsed):.2f}"
            p95 = f"{percentile(successful_elapsed, 0.95):.2f}"
            maximum = f"{max(successful_elapsed):.2f}"
        else:
            median = p95 = maximum = "—"
        print(
            f"| {metric} | {len(metric_samples)} | {len(successful_elapsed)} | "
            f"{median} | {p95} | {maximum} | "
            f"{above_target} | {critical} | {incomplete} |"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
