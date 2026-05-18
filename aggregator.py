#!/usr/bin/env python3
"""
Read io_poll.csv, filter to the last N days, emit a small columnar JSON
that the dashboard fetches and plots.

Handles both 8-column (current) and 9-column (legacy with meta_stat_ops_s)
CSV rows transparently — fixed positions for the fields we care about.
"""

import csv
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

WINDOW_DAYS = 7
SCRIPT_DIR = Path(__file__).resolve().parent
CSV_PATH = SCRIPT_DIR / "logs" / "io_poll.csv"
OUT_PATH = SCRIPT_DIR / "docs" / "data" / "latest.json"
FS_ORDER = ["HOME", "GROUP_HOME", "SCRATCH", "GROUP_SCRATCH", "OAK"]


def parse_row(row):
    """Return (timestamp, host, fs, write_MBps, meta_create_ops_s, error) or None."""
    if len(row) == 8:
        ts, host, fs_, w, _r, mc, _mu, err = row
    elif len(row) == 9:
        ts, host, fs_, w, _r, mc, _ms, _mu, err = row
    else:
        return None

    def num(x):
        try:
            return float(x) if x != "" else None
        except ValueError:
            return None

    return {
        "timestamp": ts,
        "host": host,
        "fs": fs_,
        "write_MBps": num(w),
        "meta_create_ops_s": num(mc),
        "error": err,
    }


def main():
    cutoff = datetime.now(timezone.utc) - timedelta(days=WINDOW_DAYS)

    series = {fs: {"timestamps": [], "write_MBps": [], "meta_create_ops_s": [], "errors": []}
              for fs in FS_ORDER}
    hosts = set()
    total_seen = 0
    in_window = 0

    if CSV_PATH.exists():
        with CSV_PATH.open() as f:
            for row in csv.reader(f):
                if not row or row[0] == "timestamp":
                    continue
                parsed = parse_row(row)
                if parsed is None:
                    continue
                total_seen += 1
                try:
                    ts = datetime.strptime(parsed["timestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
                except ValueError:
                    continue
                if ts < cutoff:
                    continue
                fs_ = parsed["fs"]
                if fs_ not in series:
                    continue
                in_window += 1
                hosts.add(parsed["host"])
                series[fs_]["timestamps"].append(parsed["timestamp"])
                series[fs_]["write_MBps"].append(parsed["write_MBps"])
                series[fs_]["meta_create_ops_s"].append(parsed["meta_create_ops_s"])
                series[fs_]["errors"].append(bool(parsed["error"]))
    else:
        print(f"no CSV yet at {CSV_PATH} — writing empty JSON", file=sys.stderr)

    out = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_days": WINDOW_DAYS,
        "filesystems": FS_ORDER,
        "hosts": sorted(hosts),
        "rows_in_window": in_window,
        "rows_total": total_seen,
        "series": series,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT_PATH.with_suffix(".json.tmp")
    with tmp.open("w") as f:
        json.dump(out, f, separators=(",", ":"))
    tmp.replace(OUT_PATH)
    print(f"wrote {OUT_PATH} ({in_window} rows in window, {total_seen} total)")


if __name__ == "__main__":
    main()
