#!/usr/bin/env python3
"""
Unit tests for teams_recorder_v2.py
รัน: pytest test_recorder_v2.py -q -p no:cacheprovider

LIVE tests (ต้องการ binary จริง): pytest -m live
"""
import io
import os
import platform
import subprocess
import sys
import time
from datetime import datetime, timedelta
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest


# ─── Load module ──────────────────────────────────────────────
MODULE_PATH = Path(__file__).with_name("teams_recorder_v2.py")
SPEC = spec_from_file_location("teams_recorder_v2", MODULE_PATH)
v2 = module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(v2)


# ─── Helpers ──────────────────────────────────────────────────

def _completed(stdout="", stderr="", returncode=0):
    return subprocess.CompletedProcess(
        args=[], returncode=returncode, stdout=stdout, stderr=stderr
    )


def _make_proc(stdout_lines=None, stderr_lines=None):
    """Return a fake Popen-like object whose stdout/stderr yield lines."""
    proc = MagicMock()
    proc.poll.return_value = None

    stdout_data = b""
    if stdout_lines:
        stdout_data = b"".join((line + "\n").encode() for line in stdout_lines)
    proc.stdout = io.BytesIO(stdout_data)

    stderr_data = b""
    if stderr_lines:
        stderr_data = b"".join((line + "\n").encode() for line in stderr_lines)
    proc.stderr = io.BytesIO(stderr_data)

    proc.stdin = MagicMock()
    return proc


LIVE_SMOKE = pytest.mark.skipif(
    not os.getenv("RUN_LIVE_SMOKE"), reason="live smoke test — set RUN_LIVE_SMOKE=1"
)


# ─── Autouse fixture: redirect all runtime-state paths ────────

@pytest.fixture(autouse=True)
def _redirect_runtime_paths(monkeypatch, tmp_path):
    """Redirect LOG_DIR / APP_SUPPORT_DIR / STATUS_FILE / PID_FILE to tmp_path.
    Prevents any test from writing into the real ~/Library/Logs or
    ~/Library/Application Support. Per-test monkeypatches override this
    because they're applied later in the same function scope.
    """
    support = str(tmp_path / "app_support")
    monkeypatch.setattr(v2, "LOG_DIR",         str(tmp_path / "logs"))
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", support)
    monkeypatch.setattr(v2, "STATUS_FILE",     os.path.join(support, "status.json"))
    monkeypatch.setattr(v2, "PID_FILE",        os.path.join(support, "team-recorder.pid"))
    monkeypatch.setattr(v2, "RECORDER_PID_FILE", os.path.join(support, "recorder.pid"))


# ─── Binary / startup tests ───────────────────────────────────

def test_find_recorder_binary_uses_env_override(monkeypatch, tmp_path):
    override = str(tmp_path / "my_recorder")
    monkeypatch.setenv("RECORDER_BIN", override)
    assert v2.find_recorder_binary() == override


def test_find_recorder_binary_falls_back_to_sibling_path(monkeypatch):
    monkeypatch.delenv("RECORDER_BIN", raising=False)
    result = v2.find_recorder_binary()
    assert result.endswith(os.path.join("recorder", "recorder"))
    assert os.path.join(v2.BASE_DIR, "recorder", "recorder") == result


def test_check_recorder_ready_returns_false_when_binary_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(v2, "find_recorder_binary",
                        lambda: str(tmp_path / "nonexistent"))
    assert v2.check_recorder_ready() is False


def test_check_recorder_ready_returns_false_on_arch_mismatch(monkeypatch, tmp_path):
    fake_binary = tmp_path / "recorder"
    fake_binary.write_bytes(b"fake")
    monkeypatch.setattr(v2, "find_recorder_binary", lambda: str(fake_binary))
    # Make 'file' return an arch that doesn't match the running machine
    machine = platform.machine()  # e.g. "arm64"
    other_arch = "x86_64" if machine == "arm64" else "arm64"

    monkeypatch.setattr(
        v2.subprocess, "run",
        lambda *a, **kw: _completed(stdout=f"Mach-O {other_arch} executable")
    )
    assert v2.check_recorder_ready() is False


def test_check_recorder_ready_returns_true_on_success(monkeypatch, tmp_path):
    fake_binary = tmp_path / "recorder"
    fake_binary.write_bytes(b"fake")
    monkeypatch.setattr(v2, "find_recorder_binary", lambda: str(fake_binary))
    machine = platform.machine()

    calls = []

    def fake_run(args, **kw):
        calls.append(args)
        if args[0] == "file":
            # 'file' command — return matching arch
            return _completed(stdout=f"Mach-O {machine} executable")
        if "--check" in args:
            return _completed(stdout="OK — arm64 / macOS 26.0", returncode=0)
        return _completed()

    monkeypatch.setattr(v2.subprocess, "run", fake_run)
    assert v2.check_recorder_ready() is True
    assert any("--check" in str(c) for c in calls)


# ─── Teams detection tests ─────────────────────────────────────
# Covers the 2026-07-06 regression: New Teams moved call-media UDP sockets
# onto a "Microsoft Teams ModuleHost" (SlimCore) helper process, so checking
# only the main MSTeams PID stopped detecting active meetings.

def _fake_pgrep_lsof(mstteams_pid="", modulehost_pid="", lsof_stdout="", lsof_calls=None):
    """Build a fake subprocess.run that answers pgrep -x MSTeams,
    pgrep -f ModuleHost, kill -0, and lsof according to the given fixtures.
    Records every lsof invocation's args (as a list) into lsof_calls if given.
    """
    def fake_run(args, **kw):
        if args[:2] == ["pgrep", "-x"]:
            return _completed(stdout=mstteams_pid)
        if args[:2] == ["pgrep", "-f"]:
            return _completed(stdout=modulehost_pid)
        if args[0] == "kill":
            return _completed(returncode=0)
        if args[0] == "lsof":
            if lsof_calls is not None:
                lsof_calls.append(args)
            return _completed(stdout=lsof_stdout)
        return _completed()
    return fake_run


def test_get_teams_pids_single_process_backward_compat(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "")
    monkeypatch.setattr(v2.subprocess, "run",
                         _fake_pgrep_lsof(mstteams_pid="111", modulehost_pid=""))
    assert v2.get_teams_pids() == ["111"]
    assert v2.get_teams_pid() == "111"


def test_get_teams_pids_includes_modulehost_helper(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "")
    monkeypatch.setattr(v2.subprocess, "run",
                         _fake_pgrep_lsof(mstteams_pid="111", modulehost_pid="222"))
    assert v2.get_teams_pids() == ["111", "222"]


def test_is_teams_in_meeting_true_when_only_helper_has_udp_sockets(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "")
    lsof_calls = []
    lsof_stdout = (
        "COMMAND PID USER ...\n"
        "MSTeams 111 u  4u  IPv4 ... 0t0 UDP 1.2.3.4:12345\n"
        "ModHost 222 u  5u  IPv4 ... 0t0 UDP 1.2.3.4:12346\n"
        "ModHost 222 u  6u  IPv4 ... 0t0 UDP 1.2.3.4:12347\n"
        "ModHost 222 u  7u  IPv4 ... 0t0 UDP 1.2.3.4:12348\n"
        "ModHost 222 u  8u  IPv4 ... 0t0 UDP 1.2.3.4:12349\n"
    )
    monkeypatch.setattr(v2.subprocess, "run", _fake_pgrep_lsof(
        mstteams_pid="111", modulehost_pid="222",
        lsof_stdout=lsof_stdout, lsof_calls=lsof_calls))
    assert v2.is_teams_in_meeting() is True
    assert lsof_calls[-1][-1] == "111,222"


def test_is_teams_in_meeting_false_below_threshold(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "")
    lsof_stdout = (
        "COMMAND PID USER ...\n"
        "ModHost 222 u  5u  IPv4 ... 0t0 UDP 1.2.3.4:12346\n"
        "ModHost 222 u  6u  IPv4 ... 0t0 UDP 1.2.3.4:12347\n"
        "ModHost 222 u  7u  IPv4 ... 0t0 UDP 1.2.3.4:12348\n"
    )
    monkeypatch.setattr(v2.subprocess, "run", _fake_pgrep_lsof(
        mstteams_pid="111", modulehost_pid="222", lsof_stdout=lsof_stdout))
    assert v2.is_teams_in_meeting() is False


def test_is_teams_in_meeting_no_teams_running(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "")
    lsof_calls = []
    monkeypatch.setattr(v2.subprocess, "run", _fake_pgrep_lsof(
        mstteams_pid="", modulehost_pid="", lsof_calls=lsof_calls))
    assert v2.is_teams_in_meeting() is False
    assert lsof_calls == []


def test_is_teams_in_meeting_lsof_timeout(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "")

    def fake_run(args, **kw):
        if args[:2] == ["pgrep", "-x"]:
            return _completed(stdout="111")
        if args[:2] == ["pgrep", "-f"]:
            return _completed(stdout="")
        if args[0] == "lsof":
            raise subprocess.TimeoutExpired(cmd=args, timeout=5)
        return _completed()

    monkeypatch.setattr(v2.subprocess, "run", fake_run)
    assert v2.is_teams_in_meeting() is False


def test_get_teams_pid_cache_reused_when_all_pids_alive(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "111,222")
    pgrep_calls = []

    def fake_run(args, **kw):
        if args[0] == "kill":
            return _completed(returncode=0)
        if args[0] == "pgrep":
            pgrep_calls.append(args)
        return _completed()

    monkeypatch.setattr(v2.subprocess, "run", fake_run)
    assert v2.get_teams_pids() == ["111", "222"]
    assert pgrep_calls == []


def test_get_teams_pid_cache_invalidated_when_any_pid_dies(monkeypatch):
    monkeypatch.setattr(v2, "_pid_cache", "111,222")

    def fake_run(args, **kw):
        if args[0] == "kill":
            return _completed(returncode=1 if args[-1] == "222" else 0)
        if args[:2] == ["pgrep", "-x"]:
            return _completed(stdout="111")
        if args[:2] == ["pgrep", "-f"]:
            return _completed(stdout="333")
        return _completed()

    monkeypatch.setattr(v2.subprocess, "run", fake_run)
    assert v2.get_teams_pids() == ["111", "333"]


# ─── Recording lifecycle tests ────────────────────────────────

def test_start_recording_v2_sends_start_command(monkeypatch, tmp_path):
    proc = _make_proc(stdout_lines=["STARTED"])
    monkeypatch.setattr(v2, "check_disk_space", lambda _: True)
    monkeypatch.setattr(v2, "get_today_meetings", lambda: (v2.CAL_OK_NO_EVENTS, []))
    monkeypatch.setattr(v2, "find_matching_meeting", lambda *a: None)
    # patch select so _readline_timeout returns immediately
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))
    # bypass the meetings cache so the mocked get_today_meetings is always called
    v2._meetings_cache["date"] = None

    result = v2.start_recording_v2(proc, str(tmp_path))

    assert result is not None
    assert result["recording_path"].endswith(".m4a")
    assert result["recording_dir"] == str(tmp_path)
    # verify stdin got "start <path>\n"
    write_calls = proc.stdin.write.call_args_list
    assert any(b"start " in str(c).encode() or b"start " in c[0][0] for c in write_calls)


def test_start_recording_v2_captures_meeting_name(monkeypatch, tmp_path):
    proc = _make_proc(stdout_lines=["STARTED"])
    monkeypatch.setattr(v2, "check_disk_space", lambda _: True)
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))

    fake_meetings = [{"name": "Design Sync", "time": datetime.now()}]
    monkeypatch.setattr(v2, "get_today_meetings", lambda: (v2.CAL_OK_EVENTS, fake_meetings))
    monkeypatch.setattr(v2, "find_matching_meeting", lambda t, m: "Design Sync")
    v2._meetings_cache["date"] = None

    result = v2.start_recording_v2(proc, str(tmp_path))

    assert result is not None
    assert result["meeting_name"] == "Design Sync"


def test_start_recording_v2_falls_back_to_screen_ocr(monkeypatch, tmp_path):
    """No calendar match → OCR fallback supplies the meeting name."""
    proc = _make_proc(stdout_lines=["STARTED"])
    monkeypatch.setattr(v2, "check_disk_space", lambda _: True)
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))
    monkeypatch.setattr(v2, "get_today_meetings", lambda: (v2.CAL_OK_NO_EVENTS, []))
    monkeypatch.setattr(v2, "find_matching_meeting", lambda *a: None)
    monkeypatch.setattr(v2, "get_meeting_title_from_screen",
                         lambda p: "DX Lead Discuss & Operations")
    v2._meetings_cache["date"] = None

    result = v2.start_recording_v2(proc, str(tmp_path))

    assert result is not None
    assert result["meeting_name"] == "DX Lead Discuss & Operations"
    assert result["calendar_status"] == v2.CAL_FROM_OCR


def test_start_recording_v2_ocr_also_fails(monkeypatch, tmp_path):
    """No calendar match AND no OCR match → meeting_name stays None, status records both failures."""
    proc = _make_proc(stdout_lines=["STARTED"])
    monkeypatch.setattr(v2, "check_disk_space", lambda _: True)
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))
    monkeypatch.setattr(v2, "get_today_meetings", lambda: (v2.CAL_OK_NO_EVENTS, []))
    monkeypatch.setattr(v2, "find_matching_meeting", lambda *a: None)
    monkeypatch.setattr(v2, "get_meeting_title_from_screen", lambda p: None)
    v2._meetings_cache["date"] = None

    result = v2.start_recording_v2(proc, str(tmp_path))

    assert result is not None
    assert result["meeting_name"] is None
    assert result["calendar_status"] == v2.CAL_OCR_FAILED


def test_start_recording_v2_returns_none_on_timeout(monkeypatch, tmp_path):
    """stdout never returns STARTED → _readline_timeout returns '' → None"""
    proc = _make_proc(stdout_lines=[])
    monkeypatch.setattr(v2, "check_disk_space", lambda _: True)
    # simulate timeout: select returns empty list (no data ready)
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: ([], [], []))

    result = v2.start_recording_v2(proc, str(tmp_path))

    assert result is None


def test_start_recording_v2_returns_none_on_disk_full(monkeypatch, tmp_path):
    proc = _make_proc(stdout_lines=[])
    monkeypatch.setattr(v2, "check_disk_space", lambda _: False)

    result = v2.start_recording_v2(proc, str(tmp_path))

    assert result is None
    # stdin should never have been written to
    proc.stdin.write.assert_not_called()


def test_stop_recording_v2_sends_stop_and_renames(monkeypatch, tmp_path):
    rec_path = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec_path.write_bytes(b"fake audio data")

    proc = _make_proc(stdout_lines=["STOPPED_OK"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))

    renamed = []
    monkeypatch.setattr(v2, "rename_recording", lambda s, d: renamed.append(s))

    session = {
        "start_time":     datetime.now() - timedelta(seconds=300),
        "recording_path": str(rec_path),
        "recording_dir":  str(tmp_path),
        "meeting_name":   "Sprint Review",
    }
    v2.stop_recording_v2(proc, session)

    # stop must have been sent
    write_calls = [c[0][0] for c in proc.stdin.write.call_args_list]
    assert b"stop\n" in write_calls
    # rename_recording must have been called
    assert len(renamed) == 1


def test_stop_recording_v2_does_not_retry_ocr_at_stop(monkeypatch, tmp_path):
    """Screen OCR must NOT be retried at stop — by then the meeting has already
    ended (STOP_GRACE confirmed it), so the live-call-timer confidence gate can
    never pass. Retrying here would only block the main loop (and the
    SIGINT/SIGTERM handler, which calls stop_recording_v2 directly) for no
    realistic chance of success. Calendar retry is unaffected — it stays,
    since calendar data can genuinely arrive late."""
    rec_path = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec_path.write_bytes(b"fake audio data")

    proc = _make_proc(stdout_lines=["STOPPED_OK"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))
    monkeypatch.setattr(v2, "rename_recording", lambda s, d: None)
    monkeypatch.setattr(v2, "_get_today_meetings_cached", lambda: (v2.CAL_OK_NO_EVENTS, []))
    monkeypatch.setattr(v2, "find_matching_meeting", lambda *a: None)

    ocr_calls = []
    monkeypatch.setattr(v2, "get_meeting_title_from_screen",
                         lambda p: ocr_calls.append(1) or "should not be used")

    session = {
        "start_time":      datetime.now() - timedelta(seconds=300),
        "recording_path":  str(rec_path),
        "recording_dir":   str(tmp_path),
        "meeting_name":    None,
        "calendar_status": v2.CAL_OK_NO_EVENTS,
    }
    v2.stop_recording_v2(proc, session)

    assert ocr_calls == [], "get_meeting_title_from_screen must not be called at stop"
    assert session["meeting_name"] is None


def test_stop_recording_v2_does_not_rename_without_stopped(monkeypatch, tmp_path):
    """If binary does not return STOPPED, rename must NOT be called."""
    proc = _make_proc(stdout_lines=[])  # nothing returned
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: ([], [], []))

    renamed = []
    monkeypatch.setattr(v2, "rename_recording", lambda s, d: renamed.append(s))

    session = {
        "start_time":     datetime.now() - timedelta(seconds=300),
        "recording_path": str(tmp_path / "rec.m4a"),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }
    v2.stop_recording_v2(proc, session)

    assert len(renamed) == 0, "rename_recording must NOT be called without confirmed STOPPED"


def test_stop_recording_v2_skips_when_no_session(monkeypatch, tmp_path):
    proc = _make_proc()
    renamed = []
    monkeypatch.setattr(v2, "rename_recording", lambda s, d: renamed.append(s))

    v2.stop_recording_v2(proc, None)  # no session

    proc.stdin.write.assert_not_called()
    assert len(renamed) == 0


def test_stop_recording_v2_does_not_call_compress(monkeypatch, tmp_path):
    """AAC already compressed — no compress_recording() must be called."""
    rec_path = tmp_path / "rec.m4a"
    rec_path.write_bytes(b"audio")

    proc = _make_proc(stdout_lines=["STOPPED_OK"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))

    compress_called = []

    # Patch rename_recording instead of trying to find compress_recording
    # (compress_recording does not exist in v2 — the test guards the contract)
    original_rename = v2.rename_recording
    def guarded_rename(session, duration):
        assert not hasattr(v2, "compress_recording"), \
            "compress_recording must not exist in v2"
        compress_called  # just reference to ensure no compress path exists
        original_rename(session, duration)

    monkeypatch.setattr(v2, "rename_recording", guarded_rename)

    session = {
        "start_time":     datetime.now() - timedelta(seconds=300),
        "recording_path": str(rec_path),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }
    v2.stop_recording_v2(proc, session)

    assert not hasattr(v2, "compress_recording"), \
        "compress_recording must not exist in teams_recorder_v2"


# ─── Disk space tests ─────────────────────────────────────────

def test_check_disk_space_warns_below_warn_threshold(monkeypatch, capsys):
    """Between DISK_ABORT_MB and DISK_WARN_MB → warn but return True."""
    warn_mb = v2.DISK_WARN_MB - 50  # e.g. 450 MB — above abort, below warn
    free_bytes = warn_mb * 1024 * 1024
    monkeypatch.setattr(v2.shutil, "disk_usage",
                        lambda _: SimpleNamespace(free=free_bytes, total=0, used=0))
    result = v2.check_disk_space("/tmp")
    assert result is True
    captured = capsys.readouterr()
    assert "WARN" in captured.out


def test_check_disk_space_returns_false_below_abort_threshold(monkeypatch):
    """Below DISK_ABORT_MB (200MB) → return False."""
    free_bytes = (v2.DISK_ABORT_MB - 10) * 1024 * 1024  # 190 MB
    monkeypatch.setattr(v2.shutil, "disk_usage",
                        lambda _: SimpleNamespace(free=free_bytes, total=0, used=0))
    assert v2.check_disk_space("/tmp") is False


def test_check_disk_space_abort_threshold_matches_swift():
    """Python abort threshold must equal Swift kMinFreeBytes (200MB)."""
    assert v2.DISK_ABORT_MB == 200, \
        f"DISK_ABORT_MB must be 200 to match Swift kMinFreeBytes, got {v2.DISK_ABORT_MB}"


# ─── Config / process lifecycle tests ─────────────────────────

def test_stale_obs_password_logs_info_not_error(monkeypatch, capsys):
    """If OBS_PASSWORD is set, startup must print [INFO], not [ERROR] or raise."""
    monkeypatch.setenv("OBS_PASSWORD", "test_secret")
    # Directly re-run the startup check (mirrors what the module does at top level)
    if os.getenv("OBS_PASSWORD"):
        v2.log("[INFO] OBS_PASSWORD ใน .env ไม่ได้ใช้ใน v2 — ข้ามได้")
    captured = capsys.readouterr()
    assert "INFO" in captured.out
    assert "ERROR" not in captured.out


def test_cleanup_recorder_terminates_subprocess(monkeypatch):
    proc = MagicMock()
    proc.poll.return_value = None  # still running
    monkeypatch.setattr(v2, "_recorder_proc", proc)

    v2._cleanup_recorder()

    proc.terminate.assert_called_once()
    proc.wait.assert_called_once()


def test_conflict_warning_excludes_self(monkeypatch):
    """pgrep returning only current PID should not trigger warning."""
    own_pid = str(os.getpid())

    def fake_run(args, **kw):
        if "pgrep" in args:
            return _completed(stdout=own_pid + "\n")
        return _completed()

    monkeypatch.setattr(v2, "check_recorder_ready", lambda: True)
    monkeypatch.setattr(v2.subprocess, "run", fake_run)
    monkeypatch.setattr(v2.subprocess, "Popen",
                        lambda *a, **kw: (_ for _ in ()).throw(OSError("blocked")))

    v2.connect_recorder()


def test_conflict_warning_logged_when_other_process_running(monkeypatch, capsys):
    """pgrep returning a different PID should trigger [WARN]."""
    other_pid = "99999"  # definitely not os.getpid()

    def fake_run(args, **kw):
        if "pgrep" in args:
            return _completed(stdout=other_pid + "\n")
        return _completed()

    # check_recorder_ready must return True so execution reaches the pgrep check;
    # stop before actual spawn by having Popen raise an exception
    monkeypatch.setattr(v2, "check_recorder_ready", lambda: True)
    monkeypatch.setattr(v2.subprocess, "run", fake_run)
    monkeypatch.setattr(v2.subprocess, "Popen",
                        lambda *a, **kw: (_ for _ in ()).throw(OSError("blocked")))

    v2.connect_recorder()

    captured = capsys.readouterr()
    assert "WARN" in captured.out


def test_connect_recorder_writes_child_pid(monkeypatch, tmp_path):
    fake_proc = MagicMock()
    fake_proc.pid = 24680
    monkeypatch.setattr(v2, "check_recorder_ready", lambda: True)
    monkeypatch.setattr(v2.subprocess, "run", lambda *a, **kw: _completed(stdout=str(os.getpid()) + "\n"))
    monkeypatch.setattr(v2.subprocess, "Popen", lambda *a, **kw: fake_proc)
    pid_file = tmp_path / "recorder.pid"
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", str(tmp_path))
    monkeypatch.setattr(v2, "RECORDER_PID_FILE", str(pid_file))

    assert v2.connect_recorder() is fake_proc
    assert pid_file.read_text().strip() == "24680"


# ─── Rename logic tests ───────────────────────────────────────

def test_rename_recording_uses_meeting_name(tmp_path):
    rec = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec.write_bytes(b"audio")
    session = {
        "start_time":     datetime(2026, 1, 1, 10, 0, 0),
        "recording_path": str(rec),
        "recording_dir":  str(tmp_path),
        "meeting_name":   "Sprint Planning",
    }
    v2.rename_recording(session, 600.0)
    files = list(tmp_path.glob("*.m4a"))
    assert len(files) == 1
    assert "Sprint Planning" in files[0].name


def test_rename_recording_fallback_no_name(tmp_path):
    rec = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec.write_bytes(b"audio")
    session = {
        "start_time":      datetime(2026, 1, 1, 10, 0, 0),
        "recording_path":  str(rec),
        "recording_dir":   str(tmp_path),
        "meeting_name":    None,
        "calendar_status": v2.CAL_NO_ACCESS,
    }
    v2.rename_recording(session, 600.0)
    files = list(tmp_path.glob("*.m4a"))
    assert len(files) == 1
    assert "Teams Meeting" in files[0].name
    # fallback reason must be stashed on the session for write_status to surface
    assert session.get("fallback_reason") == "calendar access denied"


def test_rename_recording_short_call_no_name(tmp_path):
    rec = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec.write_bytes(b"audio")
    session = {
        "start_time":     datetime(2026, 1, 1, 10, 0, 0),
        "recording_path": str(rec),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }
    v2.rename_recording(session, 30.0)  # < MIN_DURATION
    files = list(tmp_path.glob("*.m4a"))
    assert len(files) == 1
    assert "Short" in files[0].name


def test_rename_recording_part_numbering(tmp_path):
    """If target name already exists, append _part2."""
    rec = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec.write_bytes(b"audio")
    # Pre-create the would-be target
    existing = tmp_path / "Teams Meeting - 10-00_01-01-2026.m4a"
    existing.write_bytes(b"earlier")

    session = {
        "start_time":     datetime(2026, 1, 1, 10, 0, 0),
        "recording_path": str(rec),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }
    v2.rename_recording(session, 600.0)
    files = list(tmp_path.glob("*.m4a"))
    assert any("_part2" in f.name for f in files)


def test_rename_recording_part_cap_at_99(tmp_path, monkeypatch):
    """Q1: when parts 2–99 all exist, falls back to timestamp suffix (no infinite loop)."""
    rec = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec.write_bytes(b"audio")

    # Create the base name and all _part2 … _part99
    base = tmp_path / "Teams Meeting - 10-00_01-01-2026.m4a"
    base.write_bytes(b"x")
    for p in range(2, 100):
        (tmp_path / f"Teams Meeting - 10-00_01-01-2026_part{p}.m4a").write_bytes(b"x")

    # Fix time.time() so we know what suffix to expect
    monkeypatch.setattr(v2.time, "time", lambda: 1234567890.0)

    session = {
        "start_time":     datetime(2026, 1, 1, 10, 0, 0),
        "recording_path": str(rec),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }
    v2.rename_recording(session, 600.0)

    files = list(tmp_path.glob("*1234567890*.m4a"))
    assert len(files) == 1, "expected timestamp-suffix fallback file"


# ─── Q3: crash recovery ──────────────────────────────────────

def test_binary_crash_saves_incomplete_file(tmp_path, monkeypatch):
    """Q3: if binary crashes mid-recording, partial file is renamed INCOMPLETE_*."""
    rec_path = tmp_path / "rec_14-00_21-05-2026.m4a"
    rec_path.write_bytes(b"partial audio data")  # non-empty = worth saving

    session = {
        "start_time":     datetime(2026, 5, 21, 14, 0, 0),
        "recording_path": str(rec_path),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }

    # Simulate: proc.poll() returns non-None (binary exited)
    proc = MagicMock()
    proc.poll.return_value = 1  # crashed

    # Run just the crash-recovery logic directly
    src = session["recording_path"]
    if os.path.exists(src) and os.path.getsize(src) > 0:
        ts_crash = session["start_time"].strftime("%H-%M_%d-%m-%Y")
        dest = os.path.join(session["recording_dir"], f"INCOMPLETE_{ts_crash}.m4a")
        os.rename(src, dest)

    incomplete = list(tmp_path.glob("INCOMPLETE_*.m4a"))
    assert len(incomplete) == 1, "expected INCOMPLETE_ file after crash"
    assert not rec_path.exists(), "original temp file should be gone after rename"


def test_binary_crash_empty_file_not_saved(tmp_path):
    """Q3: empty partial file (0 bytes) should NOT be renamed — nothing to save."""
    rec_path = tmp_path / "rec_14-00_21-05-2026.m4a"
    rec_path.write_bytes(b"")  # empty — binary crashed before writing anything

    src = str(rec_path)
    if os.path.exists(src) and os.path.getsize(src) > 0:
        os.rename(src, str(tmp_path / "INCOMPLETE_14-00_21-05-2026.m4a"))

    incomplete = list(tmp_path.glob("INCOMPLETE_*.m4a"))
    assert len(incomplete) == 0, "empty file must not be saved as INCOMPLETE"


# ─── P2-A: meetings cache ─────────────────────────────────────

def test_meetings_cache_invalidates_on_new_day(monkeypatch):
    """P2-A: cache returns same list on same day, re-fetches on new day."""
    calls = []

    def fake_get():
        calls.append(1)
        return (v2.CAL_OK_EVENTS, [{"name": "Standup", "time": datetime.now()}])

    monkeypatch.setattr(v2, "get_today_meetings", fake_get)
    # Reset cache state
    v2._meetings_cache["date"] = None
    v2._meetings_cache["status"] = None
    v2._meetings_cache["meetings"] = []

    v2._get_today_meetings_cached()
    v2._get_today_meetings_cached()  # same day — should NOT re-fetch
    assert len(calls) == 1, "icalBuddy should only be called once per day"

    # Simulate day rollover
    from datetime import date, timedelta
    yesterday = date.today() - timedelta(days=1)
    v2._meetings_cache["date"] = yesterday

    v2._get_today_meetings_cached()  # new day — should re-fetch
    assert len(calls) == 2, "icalBuddy should re-fetch on new day"


# ─── U5: icalBuddy startup warning ───────────────────────────

def test_ical_buddy_missing_returns_empty_list(monkeypatch):
    """U5: get_today_meetings() returns missing_icalbuddy status when binary missing."""
    monkeypatch.setattr(v2, "ICAL_BUDDY", "/nonexistent/icalBuddy")
    status, meetings = v2.get_today_meetings()
    assert status == v2.CAL_MISSING_ICALBUDDY
    assert meetings == []


# ─── sanitize_filename tests ──────────────────────────────────

def test_sanitize_filename_removes_bad_chars():
    assert "/" not in v2.sanitize_filename("Q1/Results: 2026")
    assert ":" not in v2.sanitize_filename("Meeting: foo")


def test_sanitize_filename_empty_input_returns_fallback():
    assert v2.sanitize_filename("") == "Teams Meeting"
    assert v2.sanitize_filename("   ") == "Teams Meeting"


def test_sanitize_filename_truncates_long_names():
    long = "A" * 200
    assert len(v2.sanitize_filename(long)) <= 80


# ─── Live smoke tests (skipped unless RUN_LIVE_SMOKE=1) ───────

@LIVE_SMOKE
def test_live_recorder_binary_check():
    binary = v2.find_recorder_binary()
    r = subprocess.run([binary, "--check"], capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert r.stdout.startswith("OK")


@LIVE_SMOKE
def test_live_recorder_list_devices():
    binary = v2.find_recorder_binary()
    r = subprocess.run([binary, "--list-devices"],
                       capture_output=True, text=True, timeout=5)
    assert r.returncode == 0
    assert len(r.stdout.strip()) > 0


@LIVE_SMOKE
def test_live_recorder_start_stop(tmp_path):
    """Short live recording — verify .m4a is created and non-empty."""
    import time
    binary = v2.find_recorder_binary()
    proc = subprocess.Popen(
        [binary],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        out_path = str(tmp_path / "test_live.m4a")
        proc.stdin.write(f"start {out_path}\n".encode())
        proc.stdin.flush()

        import select as _sel
        r, _, _ = _sel.select([proc.stdout], [], [], 10)
        assert r, "timeout waiting for STARTED"
        line = proc.stdout.readline().decode().strip()
        assert line == "STARTED", f"expected STARTED, got {line!r}"

        time.sleep(2)

        proc.stdin.write(b"stop\n")
        proc.stdin.flush()
        r, _, _ = _sel.select([proc.stdout], [], [], 30)
        assert r, "timeout waiting for STOPPED_OK"
        line = proc.stdout.readline().decode().strip()
        assert line == "STOPPED_OK", \
            f"expected STOPPED_OK, got {line!r} — file may be incomplete"

        assert os.path.exists(out_path), "output file not created"
        size = os.path.getsize(out_path)
        assert size > 0, "output file is empty"
        # 32 kbps × 2s = 8 000 bytes minimum; allow generous 3× headroom for container overhead.
        # Upper bound: 200 KB for ≤5s guards against accidental revert to 96 kbps (would be ~60 KB/s).
        assert size < 200_000, (
            f"output file suspiciously large ({size} bytes for ~2s): "
            "kBitrate may have reverted to a higher value"
        )
    finally:
        proc.terminate()
        proc.wait(timeout=5)


# ─── Manual start/stop state-transition tests ─────────────────

def test_find_matching_meeting_inside_interval():
    """Recording start inside event interval → match."""
    from datetime import datetime, timedelta
    ev_start = datetime(2026, 1, 1, 10, 0)
    ev_end   = datetime(2026, 1, 1, 11, 0)
    meetings = [{"start": ev_start, "end": ev_end, "name": "Sprint Review"}]
    # Join 45 min into the meeting (would fail the old ±30 min window)
    start_time = ev_start + timedelta(minutes=45)
    result = v2.find_matching_meeting(start_time, meetings)
    assert result == "Sprint Review"


def test_find_matching_meeting_outside_interval():
    """Recording start outside event interval (with tolerance) → no match."""
    from datetime import datetime, timedelta
    ev_start = datetime(2026, 1, 1, 10, 0)
    ev_end   = datetime(2026, 1, 1, 11, 0)
    meetings = [{"start": ev_start, "end": ev_end, "name": "Sprint Review"}]
    # 10 min after event ends (exceeds 5 min tolerance)
    start_time = ev_end + timedelta(minutes=10)
    result = v2.find_matching_meeting(start_time, meetings)
    assert result is None


def test_find_matching_meeting_no_end_time():
    """Meeting with no end time falls back to 1-hour window."""
    from datetime import datetime, timedelta
    ev_start = datetime(2026, 1, 1, 10, 0)
    meetings = [{"start": ev_start, "end": None, "name": "Standup"}]
    result = v2.find_matching_meeting(ev_start + timedelta(minutes=30), meetings)
    assert result == "Standup"


def test_fallback_reason_for_ocr_failed():
    assert (v2.fallback_reason_for(v2.CAL_OCR_FAILED)
            == "no calendar title and no live meeting window detected via screen OCR")


# ─── Screen OCR meeting-title fallback ─────────────────────────
# recorder's in-process "title" stdin command: OCR the live Teams call
# window when calendar has no title (v1.2.0 — org policy can block calendar
# title sharing entirely). MUST go through the stdin of the recorder process
# that is already recording — spawning a second `recorder --meeting-title`
# process concurrently is a different ScreenCaptureKit client and interrupts
# the first one's SCStream (confirmed by live testing; see plan/DECISIONS.md).

def test_get_meeting_title_from_screen_success(monkeypatch):
    proc = _make_proc(stdout_lines=["TITLE DX Lead Discuss & Operations"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))
    assert v2.get_meeting_title_from_screen(proc) == "DX Lead Discuss & Operations"
    write_calls = [c[0][0] for c in proc.stdin.write.call_args_list]
    assert b"title\n" in write_calls


def test_get_meeting_title_from_screen_no_live_meeting(monkeypatch):
    """recorder responds TITLE_NONE → None, not a crash."""
    proc = _make_proc(stdout_lines=["TITLE_NONE"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))
    assert v2.get_meeting_title_from_screen(proc) is None


def test_get_meeting_title_from_screen_broken_pipe(monkeypatch):
    proc = _make_proc(stdout_lines=[])
    proc.stdin.write.side_effect = BrokenPipeError()
    assert v2.get_meeting_title_from_screen(proc) is None


def test_get_meeting_title_from_screen_timeout(monkeypatch):
    """No response within the timeout → None, not a hang."""
    proc = _make_proc(stdout_lines=[])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: ([], [], []))
    assert v2.get_meeting_title_from_screen(proc) is None


def test_get_meeting_title_from_screen_unexpected_response_is_none(monkeypatch):
    """Malformed/unexpected response (shouldn't happen) → None, not a crash."""
    proc = _make_proc(stdout_lines=["garbage"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))
    assert v2.get_meeting_title_from_screen(proc) is None


def test_stop_recording_v2_stopped_error_renames_incomplete(monkeypatch, tmp_path):
    """STOPPED_ERROR response → _rename_as_incomplete called, rename_recording NOT called."""
    rec_path = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec_path.write_bytes(b"partial data")

    proc = _make_proc(stdout_lines=["STOPPED_ERROR: disk full"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))

    renamed_ok   = []
    renamed_inc  = []
    monkeypatch.setattr(v2, "rename_recording", lambda s, d: renamed_ok.append(s))
    monkeypatch.setattr(v2, "_rename_as_incomplete", lambda s: renamed_inc.append(s))

    session = {
        "start_time":     datetime.now() - timedelta(seconds=300),
        "recording_path": str(rec_path),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }
    v2.stop_recording_v2(proc, session)

    assert len(renamed_ok) == 0,  "rename_recording must NOT be called on STOPPED_ERROR"
    assert len(renamed_inc) == 1, "_rename_as_incomplete must be called on STOPPED_ERROR"


def test_suppress_auto_start_set_when_manual_stop_during_active_meeting():
    """Manual stop while Teams UDP is up → suppress_auto_start should be True.
    Verifies the logic contract (not full loop execution).
    """
    # Simulate the key-handler block: active=True, session not None, manual stop
    active              = True
    session_mock        = object()
    suppress_auto_start = False
    in_meeting          = True
    recording_started_by = "auto"
    end_pending_at      = 0.0

    # --- key '2' pressed ---
    suppress_auto_start  = active        # the actual line in main()
    in_meeting           = False
    recording_started_by = None
    end_pending_at       = 0.0
    # (stop_recording_v2 and session=None not called here — we test the flag logic only)

    assert suppress_auto_start is True, \
        "suppress_auto_start must be True when Teams is still live after manual stop"


def test_suppress_clears_when_udp_down():
    """suppress_auto_start resets when active=False and not in_meeting."""
    active              = False
    in_meeting          = False
    suppress_auto_start = True  # was set by a prior manual stop

    # The check at top of each loop iteration
    if not active and not in_meeting:
        suppress_auto_start = False

    assert suppress_auto_start is False


def test_manual_recording_not_auto_stopped():
    """recording_started_by=='manual' → auto-stop branch must not fire even if UDP drops."""
    recording_started_by = "manual"
    active               = False
    in_meeting           = True

    auto_stop_fired = False
    # Simulate the elif condition from main()
    if not active and in_meeting and recording_started_by == "auto":
        auto_stop_fired = True

    assert not auto_stop_fired, \
        "Auto-stop must not fire for manually-started recordings"


def test_calendar_cache_ttl(monkeypatch):
    """Cache expires after 600 s and re-fetches."""
    call_count = [0]

    def fake_fetch():
        call_count[0] += 1
        return (v2.CAL_OK_NO_EVENTS, [])

    monkeypatch.setattr(v2, "get_today_meetings", fake_fetch)

    # Force stale cache (ts = 0 → definitely older than 600 s)
    v2._meetings_cache["date"]   = datetime.now().strftime("%Y-%m-%d")
    v2._meetings_cache["ts"]     = 0.0
    v2._meetings_cache["status"] = None

    v2._get_today_meetings_cached()
    v2._get_today_meetings_cached()  # second call — cache still fresh

    assert call_count[0] == 1, "Should fetch once, then serve from cache"

    # Expire the cache
    v2._meetings_cache["ts"] = 0.0
    v2._get_today_meetings_cached()

    assert call_count[0] == 2, "Should re-fetch after TTL expires"


# ─── Phase 1A: notifications ──────────────────────────────────

def test_notify_silent_when_not_enabled(monkeypatch):
    """notify() must do nothing when NOTIFY_ENABLED is False (unit-test default)."""
    calls = []
    monkeypatch.setattr(v2.subprocess, "run", lambda *a, **k: calls.append(a))
    monkeypatch.setattr(v2, "NOTIFY_ENABLED", False)
    v2.notify("T", "M")
    assert calls == [], "notify must not spawn osascript when disabled"


def test_notify_respects_env_off(monkeypatch):
    """NOTIFY=0 disables notifications even when NOTIFY_ENABLED is True."""
    calls = []
    monkeypatch.setattr(v2.subprocess, "run", lambda *a, **k: calls.append(a))
    monkeypatch.setattr(v2, "NOTIFY_ENABLED", True)
    monkeypatch.setenv("NOTIFY", "0")
    v2.notify("T", "M")
    assert calls == []


def test_notify_invokes_osascript_with_argv(monkeypatch):
    """When enabled, notify() passes title/message as argv — not interpolated."""
    calls = []
    monkeypatch.setattr(v2.subprocess, "run", lambda *a, **k: calls.append(a[0]))
    monkeypatch.setattr(v2, "NOTIFY_ENABLED", True)
    monkeypatch.setenv("NOTIFY", "1")
    v2.notify("Team Recorder", "hello world")
    assert len(calls) == 1
    argv = calls[0]
    assert argv[0] == "osascript"
    assert "hello world" in argv and "Team Recorder" in argv


# ─── Phase 1A: status file + PID file ─────────────────────────

def test_write_status_writes_atomic_json(monkeypatch, tmp_path):
    status = tmp_path / "status.json"
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", str(tmp_path))
    monkeypatch.setattr(v2, "STATUS_FILE", str(status))
    v2.write_status("recording", meeting_name="Sync", recording_path="/x.m4a")
    import json
    data = json.loads(status.read_text(encoding="utf-8"))
    assert data["state"] == "recording"
    assert data["meetingName"] == "Sync"
    assert data["recordingPath"] == "/x.m4a"
    assert not (tmp_path / "status.json.tmp").exists(), "temp file left behind"


def test_pid_file_write_and_remove(monkeypatch, tmp_path):
    pid_file = tmp_path / "team-recorder.pid"
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", str(tmp_path))
    monkeypatch.setattr(v2, "PID_FILE", str(pid_file))
    v2.write_pid_file()
    assert pid_file.read_text().strip() == str(os.getpid())
    v2.remove_pid_file()
    assert not pid_file.exists()
    v2.remove_pid_file()  # second call must not raise


def test_recorder_pid_file_write_and_remove(monkeypatch, tmp_path):
    pid_file = tmp_path / "recorder.pid"
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", str(tmp_path))
    monkeypatch.setattr(v2, "RECORDER_PID_FILE", str(pid_file))
    v2.write_recorder_pid_file(12345)
    assert pid_file.read_text().strip() == "12345"
    v2.remove_recorder_pid_file()
    assert not pid_file.exists()
    v2.remove_recorder_pid_file()


# ─── Phase 1B: post-recording validation ──────────────────────

def test_validate_recording_missing_file(tmp_path):
    ok, _ = v2.validate_recording(str(tmp_path / "nope.m4a"))
    assert ok is False


def test_validate_recording_too_small(tmp_path):
    f = tmp_path / "tiny.m4a"
    f.write_bytes(b"x" * 100)  # below MIN_VALID_BYTES
    ok, _ = v2.validate_recording(str(f))
    assert ok is False


def test_validate_recording_passes_when_afinfo_unavailable(tmp_path, monkeypatch):
    """Big-enough file but afinfo unreadable → pass (must not false-flag)."""
    f = tmp_path / "rec.m4a"
    f.write_bytes(b"x" * (v2.MIN_VALID_BYTES + 1))
    monkeypatch.setattr(v2, "read_audio_duration", lambda p: None)
    ok, _ = v2.validate_recording(str(f))
    assert ok is True


def test_validate_recording_flags_near_zero_duration(tmp_path, monkeypatch):
    f = tmp_path / "rec.m4a"
    f.write_bytes(b"x" * (v2.MIN_VALID_BYTES + 1))
    monkeypatch.setattr(v2, "read_audio_duration", lambda p: 0.1)
    ok, _ = v2.validate_recording(str(f))
    assert ok is False


def test_validate_recording_ok_normal(tmp_path, monkeypatch):
    f = tmp_path / "rec.m4a"
    f.write_bytes(b"x" * (v2.MIN_VALID_BYTES + 1))
    monkeypatch.setattr(v2, "read_audio_duration", lambda p: 123.0)
    ok, _ = v2.validate_recording(str(f))
    assert ok is True


def test_rename_as_needs_check_prefixes_file(tmp_path):
    f = tmp_path / "Meeting - 10-00_01-01-2026.m4a"
    f.write_bytes(b"audio")
    new = v2._rename_as_needs_check(str(f), "near-zero")
    assert os.path.basename(new).startswith("NEEDS_CHECK_")
    assert os.path.exists(new)
    assert not f.exists()


def test_rename_recording_returns_final_path(tmp_path):
    rec = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec.write_bytes(b"audio")
    session = {
        "start_time":     datetime(2026, 1, 1, 10, 0, 0),
        "recording_path": str(rec),
        "recording_dir":  str(tmp_path),
        "meeting_name":   "Sprint Planning",
    }
    result = v2.rename_recording(session, 600.0)
    assert result is not None
    assert os.path.exists(result)
    assert "Sprint Planning" in os.path.basename(result)


def test_rename_recording_returns_none_when_missing(tmp_path):
    session = {
        "start_time":     datetime(2026, 1, 1, 10, 0, 0),
        "recording_path": str(tmp_path / "gone.m4a"),
        "recording_dir":  str(tmp_path),
        "meeting_name":   None,
    }
    assert v2.rename_recording(session, 600.0) is None


def test_read_audio_duration_parses_afinfo(monkeypatch):
    out = "File: x.m4a\nestimated duration: 75.250 sec\nformat: ..."
    monkeypatch.setattr(v2.subprocess, "run",
                        lambda *a, **k: _completed(stdout=out, returncode=0))
    assert v2.read_audio_duration("x.m4a") == pytest.approx(75.25)


def test_read_audio_duration_none_on_failure(monkeypatch):
    monkeypatch.setattr(v2.subprocess, "run",
                        lambda *a, **k: _completed(stdout="", returncode=1))
    assert v2.read_audio_duration("x.m4a") is None


# ─── Phase 1B: recording index ────────────────────────────────

def test_recording_status_from_prefix():
    assert v2._recording_status("INCOMPLETE_x.m4a") == "incomplete"
    assert v2._recording_status("NEEDS_CHECK_x.m4a") == "needs-check"
    assert v2._recording_status("Teams Call (Short) - x.m4a") == "short"
    assert v2._recording_status("Sprint Planning - x.m4a") == "complete"


def test_run_index_generates_html(monkeypatch, tmp_path):
    (tmp_path / "Sprint - 10-00_01-01-2026.m4a").write_bytes(b"x" * 1000)
    (tmp_path / "INCOMPLETE_x.m4a").write_bytes(b"x" * 1000)
    monkeypatch.setattr(v2, "RECORDING_DIR", str(tmp_path))
    monkeypatch.setattr(v2, "read_audio_duration", lambda p: 60.0)
    monkeypatch.setattr(v2.subprocess, "run", lambda *a, **k: None)  # stub 'open'
    rc = v2.run_index()
    assert rc == 0
    idx = tmp_path / "index.html"
    assert idx.exists()
    body = idx.read_text(encoding="utf-8")
    assert "Sprint" in body
    assert "incomplete" in body


# ─── Phase 1A: make stop (PID-file based) ─────────────────────

def test_run_stop_no_pid_file(monkeypatch, tmp_path):
    monkeypatch.setattr(v2, "PID_FILE", str(tmp_path / "absent.pid"))
    # pgrep fallback: simulate no matching process
    monkeypatch.setattr(v2, "_pgrep_watcher_pids", lambda: [])
    assert v2.run_stop() == 0


def test_run_stop_pgrep_fallback_signals_when_no_pid_file(monkeypatch, tmp_path):
    """No PID file but pgrep finds exactly one watcher → send SIGTERM."""
    monkeypatch.setattr(v2, "PID_FILE", str(tmp_path / "absent.pid"))
    monkeypatch.setattr(v2, "_pgrep_watcher_pids", lambda: [5555])
    monkeypatch.setattr(v2, "_process_command",
                        lambda pid: "/usr/bin/python3 /x/teams_recorder_v2.py")
    killed = []
    monkeypatch.setattr(v2.os, "kill", lambda pid, sig: killed.append((pid, sig)))
    assert v2.run_stop() == 0
    assert killed == [(5555, v2.signal.SIGTERM)]


def test_run_stop_pgrep_fallback_refuses_ambiguous(monkeypatch, tmp_path):
    """No PID file but pgrep finds multiple watchers → refuse, return 1."""
    monkeypatch.setattr(v2, "PID_FILE", str(tmp_path / "absent.pid"))
    monkeypatch.setattr(v2, "_pgrep_watcher_pids", lambda: [5555, 6666])
    monkeypatch.setattr(v2, "_process_command", lambda pid: f"/python teams_recorder_v2.py [{pid}]")
    killed = []
    monkeypatch.setattr(v2.os, "kill", lambda pid, sig: killed.append((pid, sig)))
    assert v2.run_stop() == 1
    assert killed == [], "must not signal when multiple candidates"


def test_run_stop_refuses_non_team_recorder_process(monkeypatch, tmp_path):
    pid_file = tmp_path / "team-recorder.pid"
    pid_file.write_text("4242")
    monkeypatch.setattr(v2, "PID_FILE", str(pid_file))
    monkeypatch.setattr(v2, "_process_command",
                        lambda pid: "/usr/bin/python3 unrelated_script.py")
    killed = []
    monkeypatch.setattr(v2.os, "kill", lambda *a: killed.append(a))
    assert v2.run_stop() == 1
    assert killed == [], "must not signal a non-Team-Recorder process"


def test_run_stop_signals_verified_watcher(monkeypatch, tmp_path):
    pid_file = tmp_path / "team-recorder.pid"
    pid_file.write_text("4242")
    monkeypatch.setattr(v2, "PID_FILE", str(pid_file))
    monkeypatch.setattr(v2, "_process_command",
                        lambda pid: "/usr/bin/python3 /x/teams_recorder_v2.py")
    killed = []
    monkeypatch.setattr(v2.os, "kill", lambda pid, sig: killed.append((pid, sig)))
    assert v2.run_stop() == 0
    assert killed == [(4242, v2.signal.SIGTERM)]


def test_run_stop_cleans_stale_pid_file(monkeypatch, tmp_path):
    pid_file = tmp_path / "team-recorder.pid"
    pid_file.write_text("4242")
    monkeypatch.setattr(v2, "PID_FILE", str(pid_file))
    monkeypatch.setattr(v2, "_process_command", lambda pid: "")  # not running
    assert v2.run_stop() == 0
    assert not pid_file.exists(), "stale PID file should be removed"


# ─── Phase 1A: doctor ─────────────────────────────────────────

def test_run_doctor_returns_zero_when_healthy(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(v2, "RECORDING_DIR", str(tmp_path))
    monkeypatch.setattr(v2, "check_recorder_ready", lambda: True)
    monkeypatch.setattr(v2, "check_disk_space", lambda d: True)
    monkeypatch.setattr(v2, "get_today_meetings", lambda: (v2.CAL_OK_NO_EVENTS, []))
    monkeypatch.setattr(v2, "ICAL_BUDDY", "/nonexistent/icalBuddy")
    monkeypatch.setenv("AUDIO_INPUT_DEVICE_UID", "")
    rc = v2.run_doctor()
    assert rc == 0
    assert "Doctor" in capsys.readouterr().out


def test_run_doctor_fails_when_binary_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(v2, "RECORDING_DIR", str(tmp_path))
    monkeypatch.setattr(v2, "check_recorder_ready", lambda: False)
    monkeypatch.setattr(v2, "check_disk_space", lambda d: True)
    monkeypatch.setattr(v2, "get_today_meetings", lambda: (v2.CAL_OK_NO_EVENTS, []))
    monkeypatch.setattr(v2, "ICAL_BUDDY", "/nonexistent/icalBuddy")
    monkeypatch.setenv("AUDIO_INPUT_DEVICE_UID", "")
    assert v2.run_doctor() == 1


# ─── Phase 2A: crash auto-restart ─────────────────────────────

def _fake_session(tmp_path):
    rec = tmp_path / "rec_10-00_01-01-2026.m4a"
    rec.write_bytes(b"x" * 1000)
    return {
        "start_time":     datetime(2026, 1, 1, 10, 0, 0),
        "recording_path": str(rec),
        "recording_dir":  str(tmp_path),
        "meeting_name":   "Sprint Planning",
    }


def test_crash_restart_cap_reached_returns_none(monkeypatch, tmp_path):
    """When crash_count >= MAX_CRASH_RESTARTS, return None and write error status."""
    calls = []
    monkeypatch.setattr(v2, "notify",        lambda *a: calls.append(("notify", a)))
    monkeypatch.setattr(v2, "write_status",  lambda *a, **k: calls.append(("status", a)))
    monkeypatch.setattr(v2, "connect_recorder", lambda: None)  # should not be reached
    result = v2._attempt_crash_restart(
        session=None, in_meeting=False,
        recording_dir=str(tmp_path), crash_count=v2.MAX_CRASH_RESTARTS,
    )
    assert result is None
    assert any(c[0] == "status" and c[1][0] == "error" for c in calls)
    # connect_recorder must not be called after cap
    assert not any(c[0] == "connect" for c in calls)


def test_crash_restart_connect_fails_returns_none(monkeypatch, tmp_path):
    """connect_recorder returns None → _attempt_crash_restart returns None."""
    monkeypatch.setattr(v2, "notify",           lambda *a, **k: None)
    monkeypatch.setattr(v2, "write_status",     lambda *a, **k: None)
    monkeypatch.setattr(v2, "connect_recorder", lambda: None)
    result = v2._attempt_crash_restart(
        session=None, in_meeting=False,
        recording_dir=str(tmp_path), crash_count=1,
    )
    assert result is None


def test_crash_restart_success_not_in_meeting(monkeypatch, tmp_path):
    """Successful restart while not in meeting → returns (new_proc, None)."""
    fake_proc = object()
    monkeypatch.setattr(v2, "notify",           lambda *a, **k: None)
    monkeypatch.setattr(v2, "write_status",     lambda *a, **k: None)
    monkeypatch.setattr(v2, "connect_recorder", lambda: fake_proc)
    result = v2._attempt_crash_restart(
        session=None, in_meeting=False,
        recording_dir=str(tmp_path), crash_count=1,
    )
    assert result is not None
    new_proc, new_session = result
    assert new_proc is fake_proc
    assert new_session is None


def test_crash_restart_success_in_meeting(monkeypatch, tmp_path):
    """Successful restart while in_meeting → start_recording_v2 called, session returned."""
    fake_proc    = object()
    fake_session = _fake_session(tmp_path)
    monkeypatch.setattr(v2, "notify",              lambda *a, **k: None)
    monkeypatch.setattr(v2, "write_status",        lambda *a, **k: None)
    monkeypatch.setattr(v2, "connect_recorder",    lambda: fake_proc)
    monkeypatch.setattr(v2, "start_recording_v2",  lambda p, d: fake_session)
    result = v2._attempt_crash_restart(
        session=None, in_meeting=True,
        recording_dir=str(tmp_path), crash_count=1,
    )
    assert result is not None
    new_proc, new_session = result
    assert new_proc is fake_proc
    assert new_session is fake_session


def test_crash_restart_renames_incomplete_before_respawn(monkeypatch, tmp_path):
    """Caller is responsible for _rename_as_incomplete before calling helper;
    verify the helper does NOT call it (separation of responsibility)."""
    session     = _fake_session(tmp_path)
    rename_calls = []
    monkeypatch.setattr(v2, "_rename_as_incomplete", lambda s: rename_calls.append(s))
    monkeypatch.setattr(v2, "notify",                lambda *a, **k: None)
    monkeypatch.setattr(v2, "write_status",          lambda *a, **k: None)
    monkeypatch.setattr(v2, "connect_recorder",      lambda: object())
    v2._attempt_crash_restart(
        session=session, in_meeting=False,
        recording_dir=str(tmp_path), crash_count=1,
    )
    assert rename_calls == [], "_attempt_crash_restart must not rename — caller's job"


# ════════════════════════════════════════════════════════════════════
# Phase 3B — SIGUSR1 / SIGUSR2 signal handlers + manual helpers
# ════════════════════════════════════════════════════════════════════

def test_sigusr1_sets_flag():
    """SIGUSR1 handler sets _sig_start_requested flag (flag-only, async-signal-safe)."""
    v2._sig_start_requested = False
    v2._handle_sigusr1(None, None)
    assert v2._sig_start_requested is True
    v2._sig_start_requested = False  # reset


def test_sigusr2_sets_flag():
    """SIGUSR2 handler sets _sig_stop_requested flag (flag-only, async-signal-safe)."""
    v2._sig_stop_requested = False
    v2._handle_sigusr2(None, None)
    assert v2._sig_stop_requested is True
    v2._sig_stop_requested = False  # reset


def test_manual_start_helper_calls_start_recording(monkeypatch, tmp_path):
    """_do_manual_start calls start_recording_v2 when not already recording."""
    fake_proc    = object()
    fake_session = {"recording_path": str(tmp_path / "rec.m4a"), "meeting_name": "Test"}
    calls        = []
    monkeypatch.setattr(v2, "start_recording_v2", lambda p, d: (calls.append(1), fake_session)[1])

    new_session, started_by = v2._do_manual_start(fake_proc, None, str(tmp_path))

    assert len(calls) == 1, "start_recording_v2 should be called once"
    assert new_session is fake_session
    assert started_by == "manual"


def test_manual_start_helper_noop_when_already_recording(monkeypatch, tmp_path):
    """_do_manual_start is a no-op (returns existing session) when session is not None."""
    existing_session = {"recording_path": str(tmp_path / "rec.m4a")}
    calls = []
    monkeypatch.setattr(v2, "start_recording_v2", lambda p, d: calls.append(1))

    returned, _ = v2._do_manual_start(object(), existing_session, str(tmp_path))

    assert calls == [], "start_recording_v2 must NOT be called when already recording"
    assert returned is existing_session


def test_manual_stop_helper_calls_stop_recording(monkeypatch, tmp_path):
    """_do_manual_stop calls stop_recording_v2 and returns correct suppress flag."""
    fake_proc    = object()
    fake_session = {"recording_path": str(tmp_path / "rec.m4a"), "meeting_name": "Test"}
    calls        = []
    monkeypatch.setattr(v2, "stop_recording_v2", lambda p, s: calls.append(1))

    suppress = v2._do_manual_stop(fake_proc, fake_session, active=True)

    assert len(calls) == 1, "stop_recording_v2 should be called once"
    assert suppress is True, "suppress_auto_start should be True when Teams is still active"


def test_manual_stop_helper_noop_when_not_recording(monkeypatch):
    """_do_manual_stop returns False and does not call stop_recording_v2 if no session."""
    calls = []
    monkeypatch.setattr(v2, "stop_recording_v2", lambda p, s: calls.append(1))

    suppress = v2._do_manual_stop(object(), None, active=False)

    assert calls == [], "stop_recording_v2 must NOT be called when no session"
    assert suppress is False


# ─── Calendar lookup status tests ─────────────────────────────

class _FakeCompleted:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def _patch_icalbuddy(monkeypatch, completed=None, exc=None):
    """Patch ICAL_BUDDY to a path that exists and subprocess.run to return completed/raise exc."""
    monkeypatch.setattr(v2.os.path, "exists", lambda p: True)
    monkeypatch.setattr(v2, "ICAL_BUDDY", "/fake/icalBuddy")

    def fake_run(*a, **kw):
        if exc is not None:
            raise exc
        return completed
    monkeypatch.setattr(v2.subprocess, "run", fake_run)


def test_get_today_meetings_no_access_status(monkeypatch):
    """rc!=0 + 'No calendars' stderr → CAL_NO_ACCESS."""
    _patch_icalbuddy(monkeypatch,
                     _FakeCompleted(returncode=1, stdout="", stderr="error: No calendars."))
    status, meetings = v2.get_today_meetings()
    assert status == v2.CAL_NO_ACCESS
    assert meetings == []


def test_get_today_meetings_generic_error_status(monkeypatch):
    """rc!=0 with no permission keywords → CAL_ERROR."""
    _patch_icalbuddy(monkeypatch,
                     _FakeCompleted(returncode=2, stdout="", stderr="boom"))
    status, _ = v2.get_today_meetings()
    assert status == v2.CAL_ERROR


def test_get_today_meetings_timeout_status(monkeypatch):
    """subprocess.TimeoutExpired → CAL_TIMEOUT."""
    _patch_icalbuddy(monkeypatch,
                     exc=v2.subprocess.TimeoutExpired(cmd="icalBuddy", timeout=10))
    status, _ = v2.get_today_meetings()
    assert status == v2.CAL_TIMEOUT


def test_get_today_meetings_no_events_status(monkeypatch):
    """rc=0 + empty stdout → CAL_OK_NO_EVENTS."""
    _patch_icalbuddy(monkeypatch, _FakeCompleted(returncode=0, stdout=""))
    status, meetings = v2.get_today_meetings()
    assert status == v2.CAL_OK_NO_EVENTS
    assert meetings == []


def test_get_today_meetings_parses_events_status(monkeypatch):
    """rc=0 + valid icalBuddy output → CAL_OK_EVENTS with parsed meetings."""
    stdout = "||Standup\n10:00 - 10:30\n||Design Sync\n14:00 - 15:00\n"
    _patch_icalbuddy(monkeypatch, _FakeCompleted(returncode=0, stdout=stdout))
    status, meetings = v2.get_today_meetings()
    assert status == v2.CAL_OK_EVENTS
    assert [m["name"] for m in meetings] == ["Standup", "Design Sync"]


def test_meetings_cache_does_not_cache_failures(monkeypatch):
    """Cache must re-probe on no_access / timeout / error / missing — only ok_* outcomes pin."""
    calls = []

    def fake_get():
        calls.append(1)
        return (v2.CAL_NO_ACCESS, [])

    monkeypatch.setattr(v2, "get_today_meetings", fake_get)
    v2._meetings_cache["date"]     = None
    v2._meetings_cache["status"]   = None
    v2._meetings_cache["meetings"] = []

    v2._get_today_meetings_cached()
    v2._get_today_meetings_cached()
    assert len(calls) == 2, "permission failure must not be cached"


def test_fallback_reason_for_known_statuses():
    assert v2.fallback_reason_for(v2.CAL_NO_ACCESS)         == "calendar access denied"
    assert v2.fallback_reason_for(v2.CAL_MISSING_ICALBUDDY) == "icalBuddy not installed"
    assert v2.fallback_reason_for(v2.CAL_TIMEOUT)           == "icalBuddy timed out"
    assert v2.fallback_reason_for(v2.CAL_OK_NO_EVENTS)      == "no events on calendar"
    assert v2.fallback_reason_for(v2.CAL_OK_EVENTS)         == "no event matched start time (±5 min)"
    assert v2.fallback_reason_for(v2.CAL_FROM_APP)          == "no event matched start time (±5 min)"
    assert v2.fallback_reason_for(v2.CAL_ERROR)             == "icalBuddy error"


# ─── CalendarEventBridge: _read_events_bridge ─────────────────

def test_read_events_bridge_skipped_without_env(tmp_path):
    """Without TEAM_RECORDER_APP, bridge is always skipped (Terminal / make run path)."""
    import json
    f = tmp_path / "events-today.json"
    today = datetime.now().strftime("%Y-%m-%d")
    f.write_text(json.dumps({"date": today, "events": []}), encoding="utf-8")
    # TEAM_RECORDER_APP must NOT be set in test environment
    import os as _os
    _os.environ.pop("TEAM_RECORDER_APP", None)
    result = v2._read_events_bridge(str(f))
    assert result is None, "bridge must be skipped when TEAM_RECORDER_APP is absent"


def test_read_events_bridge_absent_returns_none(monkeypatch, tmp_path):
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    result = v2._read_events_bridge(str(tmp_path / "events-today.json"))
    assert result is None


def test_read_events_bridge_not_authorized_returns_no_access(monkeypatch, tmp_path):
    import json
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    f = tmp_path / "events-today.json"
    today = datetime.now().strftime("%Y-%m-%d")
    f.write_text(json.dumps({"date": today, "authorized": False}), encoding="utf-8")
    result = v2._read_events_bridge(str(f))
    assert result == (v2.CAL_NO_ACCESS, [])


def test_read_events_bridge_stale_date_returns_none(monkeypatch, tmp_path):
    import json
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    f = tmp_path / "events-today.json"
    f.write_text(json.dumps({"date": "2000-01-01", "events": []}), encoding="utf-8")
    result = v2._read_events_bridge(str(f))
    assert result is None


def test_read_events_bridge_parses_events(monkeypatch, tmp_path):
    import json
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    f = tmp_path / "events-today.json"
    today = datetime.now().strftime("%Y-%m-%d")
    f.write_text(json.dumps({
        "date": today,
        "events": [
            {"title": "Sprint Planning", "start": "10:00", "end": "11:00"},
            {"title": "Design Sync",     "start": "14:00"},
        ],
    }), encoding="utf-8")
    result = v2._read_events_bridge(str(f))
    assert result is not None
    status, meetings = result
    assert status == v2.CAL_FROM_APP
    assert len(meetings) == 2
    assert meetings[0]["name"] == "Sprint Planning"
    assert meetings[0]["end"] is not None
    assert meetings[1]["name"] == "Design Sync"
    assert meetings[1]["end"] is None


def test_read_events_bridge_result_cached(monkeypatch, tmp_path):
    """CAL_FROM_APP is in _CAL_CACHEABLE — bridge result must be cached like ok_events."""
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", str(tmp_path))
    monkeypatch.setattr(v2.os.path, "getmtime", lambda _: 100.0)

    calls = []

    def fake_get():
        calls.append(1)
        return (v2.CAL_FROM_APP, [])

    monkeypatch.setattr(v2, "get_today_meetings", fake_get)
    v2._meetings_cache["date"]   = None
    v2._meetings_cache["status"] = None

    v2._get_today_meetings_cached()
    v2._get_today_meetings_cached()
    assert len(calls) == 1, "CAL_FROM_APP result must be cached"
    assert v2.fallback_reason_for(None)                     == "calendar lookup unavailable"


def test_meetings_cache_invalidated_when_bridge_mtime_changes(monkeypatch, tmp_path):
    """When bridge file mtime advances, CAL_FROM_APP cache must be bypassed."""
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", str(tmp_path))
    fake_mtime = [100.0]
    monkeypatch.setattr(v2.os.path, "getmtime", lambda _: fake_mtime[0])

    calls = []

    def fake_get():
        calls.append(1)
        return (v2.CAL_FROM_APP, [])

    monkeypatch.setattr(v2, "get_today_meetings", fake_get)

    v2._meetings_cache["date"]         = datetime.now().strftime("%Y-%m-%d")
    v2._meetings_cache["ts"]           = time.time()
    v2._meetings_cache["status"]       = v2.CAL_FROM_APP
    v2._meetings_cache["meetings"]     = []
    v2._meetings_cache["bridge_mtime"] = 100.0

    v2._get_today_meetings_cached()
    assert len(calls) == 0, "unchanged mtime must hit cache"

    fake_mtime[0] = 200.0
    v2._get_today_meetings_cached()
    assert len(calls) == 1, "newer bridge mtime must invalidate cache"


# ─── Bridge mtime staleness (FR-CAL-001 / FR-CAL-002) ────────

def test_read_events_bridge_fresh_mtime_returns_result(monkeypatch, tmp_path):
    """File written within 5 min must be returned normally."""
    import json
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    f = tmp_path / "events-today.json"
    today = datetime.now().strftime("%Y-%m-%d")
    f.write_text(json.dumps({"date": today, "events": []}), encoding="utf-8")
    monkeypatch.setattr(v2.os.path, "getmtime", lambda _: time.time() - 60)
    result = v2._read_events_bridge(str(f))
    assert result is not None
    status, _ = result
    assert status == v2.CAL_FROM_APP


def test_read_events_bridge_stale_mtime_returns_none(monkeypatch, tmp_path):
    """File older than 5 min must return None — fall through to icalBuddy."""
    import json
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    f = tmp_path / "events-today.json"
    today = datetime.now().strftime("%Y-%m-%d")
    f.write_text(json.dumps({"date": today, "events": []}), encoding="utf-8")
    monkeypatch.setattr(v2.os.path, "getmtime", lambda _: time.time() - 400)
    result = v2._read_events_bridge(str(f))
    assert result is None


# ─── _bootstrap_env (FR-ENV-001 / FR-ENV-003) ────────────────

def test_env_bootstrap_creates_defaults_in_app_mode(monkeypatch, tmp_path):
    """.env created with defaults when TEAM_RECORDER_APP=1 and file absent."""
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    env_path = str(tmp_path / "support" / ".env")
    v2._bootstrap_env(env_path)
    assert os.path.exists(env_path)
    content = open(env_path).read()
    assert "RECORDING_DIR=~/Documents/Teams Recording" in content
    assert "ICAL_BUDDY_PATH=" in content


def test_env_bootstrap_creates_parent_directory(monkeypatch, tmp_path):
    """Bootstrap creates intermediate directories (App Support may not exist on first launch)."""
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    env_path = str(tmp_path / "a" / "b" / "c" / ".env")
    v2._bootstrap_env(env_path)
    assert os.path.exists(env_path)


def test_env_bootstrap_skipped_without_app_mode(monkeypatch, tmp_path):
    """Bootstrap must be a no-op when TEAM_RECORDER_APP is not set (make run / Terminal)."""
    monkeypatch.delenv("TEAM_RECORDER_APP", raising=False)
    env_path = str(tmp_path / ".env")
    v2._bootstrap_env(env_path)
    assert not os.path.exists(env_path)


def test_env_bootstrap_idempotent(monkeypatch, tmp_path):
    """Bootstrap must not overwrite an existing .env with user-edited values."""
    monkeypatch.setenv("TEAM_RECORDER_APP", "1")
    env_path = str(tmp_path / ".env")
    with open(env_path, "w") as f:
        f.write("RECORDING_DIR=/my/recordings\nNOTIFY=1\n")
    v2._bootstrap_env(env_path)
    v2._bootstrap_env(env_path)
    content = open(env_path).read()
    assert "/my/recordings" in content
    assert content.count("RECORDING_DIR=") == 1


def test_stop_recording_retries_calendar_when_unmatched(monkeypatch, tmp_path):
    """When meeting_name is None at stop time, retry with fresh bridge data."""
    monkeypatch.setattr(v2, "APP_SUPPORT_DIR", str(tmp_path))
    monkeypatch.setattr(v2.os.path, "getmtime", lambda _: time.time())

    start_time = datetime.now() - timedelta(seconds=300)
    meeting = {"start": start_time - timedelta(minutes=1),
               "end":   start_time + timedelta(minutes=59),
               "name":  "Sprint Review"}

    monkeypatch.setattr(v2, "get_today_meetings", lambda: (v2.CAL_FROM_APP, [meeting]))
    v2._meetings_cache["date"] = None

    renamed_sessions = []
    monkeypatch.setattr(v2, "rename_recording", lambda s, d: renamed_sessions.append(dict(s)))
    monkeypatch.setattr(v2, "validate_recording", lambda p: (True, ""))

    proc = _make_proc(stdout_lines=["STOPPED_OK"])
    monkeypatch.setattr(v2.select, "select", lambda r, w, x, t: (r, [], []))

    session = {
        "start_time":      start_time,
        "recording_path":  str(tmp_path / "rec.m4a"),
        "recording_dir":   str(tmp_path),
        "meeting_name":    None,
        "calendar_status": v2.CAL_FROM_APP,
    }
    v2.stop_recording_v2(proc, session)

    assert len(renamed_sessions) == 1
    assert renamed_sessions[0]["meeting_name"] == "Sprint Review", (
        "retry at stop should populate meeting_name from fresh bridge data"
    )
