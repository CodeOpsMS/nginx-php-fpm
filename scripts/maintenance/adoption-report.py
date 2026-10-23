#!/usr/bin/env python3
"""Collect aggregate GitHub interest metrics using the maintainer's gh login."""

import argparse
import datetime as dt
import json
from pathlib import Path
import re
import subprocess
import urllib.parse


def github(path):
    try:
        result = subprocess.run(
            ["gh", "api", path], capture_output=True, text=True, timeout=45, check=False
        )
    except FileNotFoundError as error:
        raise SystemExit("GitHub CLI is required; install gh and sign in first.") from error
    except subprocess.TimeoutExpired:
        return None, "GitHub request timed out"
    if result.returncode:
        return None, "Unavailable: check gh authentication and repository permissions"
    try:
        return json.loads(result.stdout), None
    except json.JSONDecodeError:
        return None, "GitHub returned an invalid JSON response"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="CodeOpsMS/nginx-php-fpm")
    parser.add_argument("--output", type=Path, default=Path("build/adoption"))
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        parser.error("--repo must be owner/name")

    repository, error = github(f"repos/{args.repo}")
    if error:
        raise SystemExit(error)

    now = dt.datetime.now(dt.timezone.utc)
    report = {
        "repository": args.repo,
        "collected_at": now.isoformat(),
        "stars": repository["stargazers_count"],
        "forks": repository["forks_count"],
        "watchers": repository["subscribers_count"],
        "traffic_window_days": 14,
    }
    rows = [
        ("Stars", report["stars"]),
        ("Forks", report["forks"]),
        ("Watchers", report["watchers"]),
    ]
    for metric in ("views", "clones"):
        data, error = github(f"repos/{args.repo}/traffic/{metric}")
        if error:
            report[metric] = {"available": False, "reason": error}
            rows.append((f"{metric.title()} (last 14 days)", "Unavailable"))
        else:
            report[metric] = {
                "available": True,
                "count": data["count"],
                "uniques": data["uniques"],
                "daily": data[metric],
            }
            rows.extend([
                (f"{metric.title()} (last 14 days)", data["count"]),
                (f"Unique {metric} (last 14 days)", data["uniques"]),
            ])

    query = urllib.parse.quote(f"repo:{args.repo} is:issue label:adoption", safe="")
    reports, error = github(f"search/issues?q={query}")
    report["adoption_reports"] = (
        {"available": False, "reason": error}
        if error else {"available": True, "count": reports["total_count"]}
    )
    rows.append(("Public adoption reports (self-reported)",
                 "Unavailable" if error else reports["total_count"]))

    text = [f"# GitHub adoption snapshot: {args.repo}", "",
            f"Collected at {now.isoformat()}.", "",
            "| Metric | Value |", "| --- | --- |"]
    text.extend(f"| {name} | {value} |" for name, value in rows)
    text.extend(["", "Traffic is a rolling 14-day window. Do not add overlapping snapshots",
                 "or sum daily unique counts. Bots and maintainer activity may be included.",
                 "Stars, views, clones, and self-reports are not active-installation counts.", ""])
    args.output.mkdir(parents=True, exist_ok=True)
    stem = args.output / now.strftime("%Y-%m-%dT%H%M%S-%fZ")
    json_path = stem.with_suffix(".json")
    markdown_path = stem.with_suffix(".md")
    json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text("\n".join(text), encoding="utf-8")
    print(markdown_path)
    print(json_path)
    unavailable = [key for key in ("views", "clones", "adoption_reports")
                   if not report[key]["available"]]
    if unavailable:
        print("Unavailable metrics: " + ", ".join(unavailable))


if __name__ == "__main__":
    main()
