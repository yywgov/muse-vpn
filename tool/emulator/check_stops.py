#!/usr/bin/env python3
"""穿云 1.13.0 e2e: every stop of the VPN service must finish quickly.

e2e #16 had two in-app disconnects that each took 120 s (Stopping -> Stopped) while the app's main
thread was blocked in the core's close. The service now gives the core at most 10 s (CoreStop) and
then reports 已停止 anyway, so any Stopping -> Stopped longer than LIMIT seconds fails the run.

Also written, for the record (never fail the run):
  freezer.txt   every 'freezing <pid> com.chuanyun.app…' line (the system's cached-app freezer)
  slow_stop.txt the service's own lines about a stop that ran past its 10 s limit

usage: check_stops.py <out_dir>        reads <out_dir>/logcat.txt
       check_stops.py --self-test
"""
import re
import sys
from datetime import datetime

LIMIT = 15.0
PKG = "com.chuanyun.app"
LINE = re.compile(r"^(\d\d-\d\d) (\d\d:\d\d:\d\d\.\d{3})\s+(\d+)\s+(\d+)\s+\w\s+(.*)$")


def _ts(day, clock):
    return datetime.strptime(f"2000-{day} {clock}", "%Y-%m-%d %H:%M:%S.%f")


def stop_durations(lines):
    """[(started_at_text, seconds or None if never finished)] per Stopping, per process."""
    pending = {}
    out = []
    for raw in lines:
        m = LINE.match(raw.rstrip("\n"))
        if not m:
            continue
        day, clock, pid, _tid, rest = m.groups()
        if "A/EventHandler" not in rest:
            continue
        if rest.endswith("new status: Stopping"):
            pending.setdefault(pid, (f"{day} {clock}", _ts(day, clock)))
        elif rest.endswith("new status: Stopped") and pid in pending:
            text, t0 = pending.pop(pid)
            out.append((text, (_ts(day, clock) - t0).total_seconds()))
    for text, _t0 in pending.values():
        out.append((text, None))
    return out


def check(lines):
    """(failures, report lines)"""
    failures, report = [], []
    for text, secs in stop_durations(lines):
        if secs is None:
            report.append(f"{text} Stopping -> (still stopping at the end of the log)")
            continue
        report.append(f"{text} Stopping -> Stopped {secs:.1f}s")
        if secs > LIMIT:
            failures.append(f"stop at {text} took {secs:.1f}s (> {LIMIT:.0f}s)")
    return failures, report


def self_test():
    log = [
        "11-07 22:13:10.207  3500  3500 D A/EventHandler: new status: Stopping",
        "11-07 22:13:10.444  3500  3500 D A/EventHandler: new status: Stopped",
        "11-07 22:15:48.914  3500  3500 D A/EventHandler: new status: Stopping",
        "11-07 22:15:49.037   555   670 D ActivityManager: freezing 1649 android.process.acore",
        "11-07 22:17:49.019  3500  3500 D A/EventHandler: new status: Stopped",
        "11-07 22:19:15.669  3500  3500 D A/EventHandler: new status: Stopping",
        "11-07 22:19:25.700  3500  3500 D A/EventHandler: new status: Stopped",
    ]
    failures, report = check(log)
    assert len(report) == 3, report
    assert failures == ["stop at 11-07 22:15:48.914 took 120.1s (> 15s)"], failures
    assert check(log[:2])[0] == []
    assert check(log[-2:])[0] == []  # 10 s: the service's own limit, allowed
    print("check_stops self-test ok")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return 0
    out = sys.argv[1]
    with open(f"{out}/logcat.txt", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    failures, report = check(lines)
    frozen = [l for l in lines if "freezing" in l and PKG in l]
    slow = [l for l in lines if "A/DisconnectLog" in l and ("仍未结束" in l or "秒后才退出" in l)]
    with open(f"{out}/stops.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(report + [""] + [f"FAIL {x}" for x in failures]) + "\n")
    with open(f"{out}/freezer.txt", "w", encoding="utf-8") as f:
        f.writelines(frozen)
    with open(f"{out}/slow_stop.txt", "w", encoding="utf-8") as f:
        f.writelines(slow)
    print("\n".join(report))
    print(f"stops={len(report)} slow(>{LIMIT:.0f}s)={len(failures)} chuanyun-frozen={len(frozen)} late-close-lines={len(slow)}")
    for x in failures:
        print(f"FAIL {x}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
