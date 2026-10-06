#!/usr/bin/env python3
"""Run without touching the live desktop: python3 nixos/tests/check-lid-keep-awake.py."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/scripts/custom-lid-keep-awake"
CLAMSHELL = ROOT / "config/scripts/custom-activate-clamshell"
MENU = ROOT / "config/rofi/powermenu/power.sh"
UNIT = "custom-lid-keep-awake.service"

MOCK = r'''
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['CHECK_DIR'])
state = root / 'active'
with (root / 'log').open('a') as f:
    f.write(json.dumps([name, *args]) + '\n')
if name == 'systemctl':
    if 'is-active' in args:
        sys.exit(0 if state.exists() else 3)
    if 'stop' in args:
        assert args == ['--user', 'stop', 'custom-lid-keep-awake.service']
        if os.environ.get('FAIL_STOP'): sys.exit(1)
        state.unlink(missing_ok=True)
elif name == 'systemd-run':
    assert '--property=Type=notify' in args
    assert '--property=NotifyAccess=all' in args
    assert '--property=PartOf=graphical-session.target' in args
    assert args[-1] == 'hold'
    if os.environ.get('FAIL_ENABLE'): sys.exit(1)
    state.touch()
elif name == 'systemd-inhibit':
    assert '--what=handle-lid-switch:sleep' in args and '--mode=block' in args
    environment = dict(os.environ)
    environment.pop('NOTIFY_SOCKET', None)
    sys.exit(subprocess.run(args[4:], env=environment).returncode)
elif name == 'systemd-notify':
    assert os.environ.get('NOTIFY_SOCKET') == 'check-notify-socket'
    assert args == ['--ready']
elif name == 'custom-lock-screen':
    try: os.fstat(9)
    except OSError: pass
    else: raise AssertionError('Background lock process inherited the transition lock')
elif name == 'grep':
    sys.exit(0 if os.environ.get('LID_CLOSED') else 1)
elif name == 'hyprctl' and os.environ.get('FAIL_DISPLAY'):
    sys.exit(1)
elif name == 'rofi':
    rows = sys.stdin.read().splitlines()
    prompt = args[args.index('-p') + 1]
    if prompt == 'Are you sure?':
        print(next(row for row in rows if os.environ.get('CONFIRM', 'Yes') in row))
    else:
        print(next(row for row in rows if os.environ['MENU_ACTION'] in row))
'''


with tempfile.TemporaryDirectory(prefix="check-lid-") as temporary:
    directory = Path(temporary)
    binaries = directory / "bin"
    binaries.mkdir()
    mock = binaries / "mock"
    mock.write_text(f"#!{sys.executable}\n" + MOCK)
    mock.chmod(0o755)
    for name in ("systemctl", "systemd-run", "systemd-inhibit", "systemd-notify",
                 "custom-lock-screen", "hyprctl", "brightnessctl", "notify-send",
                 "grep", "rofi", "busctl", "sleep"):
        (binaries / name).symlink_to(mock)
    common = directory / ".config/rofi/common"
    common.mkdir(parents=True)
    (common / "generic.sh").write_text((ROOT / "config/rofi/common/generic.sh").read_text())
    environment = dict(os.environ, CHECK_DIR=temporary, HOME=temporary,
                       XDG_RUNTIME_DIR=temporary,
                       PATH=f"{binaries}:{SCRIPT.parent}:{os.environ['PATH']}")
    logfile = directory / "log"

    def run(action=None, *, script=SCRIPT, expected=0, **options):
        logfile.write_text("")
        command = ["bash", str(script)] + ([action] if action else [])
        result = subprocess.run(command, env=dict(environment, **options),
                                capture_output=True, text=True, timeout=15)
        assert result.returncode == expected, (command, result.stderr, result.returncode)
        return [json.loads(line) for line in logfile.read_text().splitlines()]

    def meaningful(calls):
        return [call for call in calls if call[0] not in ("systemctl", "grep")]

    calls = run('hold', NOTIFY_SOCKET='check-notify-socket')
    assert ["systemd-notify", "--ready"] in calls
    assert calls[-1] == ["sleep", "infinity"]
    run("status", expected=3)
    assert meaningful(run("close", script=CLAMSHELL)) == [["hyprctl", "keyword", "monitor", "eDP-1,disable"]]
    calls = run("enable", FAIL_ENABLE="1", expected=1)
    assert calls[-1][0] == "busctl"
    run("status", expected=3)
    run("toggle")
    run("status")
    assert not meaningful(run("enable"))  # No duplicate inhibitor.
    assert meaningful(run("close", script=CLAMSHELL, LID_CLOSED="1")) == [
        ["custom-lock-screen"], ["hyprctl", "dispatch", "dpms", "off"]]
    assert not meaningful(run("resume-display", LID_CLOSED="1"))
    assert meaningful(run("resume-display")) == [
        ["hyprctl", "dispatch", "dpms", "on"], ["brightnessctl", "-r"]]
    calls = run("open", script=CLAMSHELL)
    assert calls[:2] == [["hyprctl", "reload"], ["hyprctl", "dispatch", "dpms", "on"]]
    assert ["systemctl", "--user", "stop", UNIT] in calls
    run("status", expected=3)
    assert ["systemctl", "--user", "stop", UNIT] not in run("open")
    run("enable", LID_CLOSED="1")
    run("open", FAIL_DISPLAY="1", expected=1)
    run("status", expected=3)  # Reopening clears mode even if display restore fails.

    for action in ("Suspend", "Hibernate"):
        run("enable")
        calls = run(script=MENU, MENU_ACTION=action, CONFIRM="Cancel")
        assert not any("stop" in call or "suspend" in call or "hibernate" in call for call in calls)
        run("status")
        calls = run(script=MENU, MENU_ACTION=action)
        stop = calls.index(["systemctl", "--user", "stop", UNIT])
        lock = calls.index(["custom-lock-screen"])
        sleep = calls.index(["systemctl", action.lower()])
        assert stop < lock < sleep
        run("status", expected=3)
    run(script=MENU, MENU_ACTION="Lid Keep-Awake: Off")
    run("status")
    calls = run(script=MENU, MENU_ACTION="Suspend", FAIL_STOP="1", expected=1)
    assert ["systemctl", "suspend"] not in calls
    run(script=MENU, MENU_ACTION="Lid Keep-Awake: On")
    run("status", expected=3)
    run("bad-action", expected=2)
    run("bad-action", script=CLAMSHELL, expected=2)

    logfile.write_text("")
    commands = [subprocess.Popen(["bash", str(SCRIPT), "enable"], env=environment)
                for _ in range(4)]
    assert all(command.wait(timeout=15) == 0 for command in commands)
    calls = [json.loads(line) for line in logfile.read_text().splitlines()]
    assert sum(call[0] == "systemd-run" for call in calls) == 1
    run("open")
    run("status", expected=3)

print("Lid Keep-Awake checks passed (lid handling, idle resume, power menu, failures, concurrent enables).")
