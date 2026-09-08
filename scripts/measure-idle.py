#!/usr/bin/env python3
"""Measure cumulative process CPU time; does not inspect window titles or contents."""
import argparse
import json
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=float, default=30)
args = parser.parse_args()
if not 1 <= args.seconds <= 300:
    parser.error("--seconds must be between 1 and 300")

def snapshot():
    row = subprocess.check_output(["ps", "-p", str(args.pid), "-o", "time=,rss=,%cpu="], text=True).strip().split()
    if len(row) != 3:
        raise SystemExit("Process not found or ps returned an unexpected result")
    parts = row[0].split(":")
    cpu_seconds = sum(float(value) * 60 ** index for index, value in enumerate(reversed(parts)))
    return cpu_seconds, int(row[1]), float(row[2])

before = snapshot()
start = time.monotonic()
time.sleep(args.seconds)
after = snapshot()
elapsed = time.monotonic() - start
delta = after[0] - before[0]
print(json.dumps({"pid": args.pid, "wall_seconds": round(elapsed, 3),
                  "cpu_seconds_delta": round(delta, 3), "average_cpu_percent_of_one_core": round(100 * delta / elapsed, 3),
                  "rss_mib_start": round(before[1] / 1024, 2), "rss_mib_end": round(after[1] / 1024, 2)}, indent=2))
