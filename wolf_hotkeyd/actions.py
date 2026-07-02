from __future__ import annotations

import shlex
import subprocess
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass

from wolf_hotkeyd.config import HotkeyConfig
from wolf_hotkeyd.hotkeys import HotkeyEvent


@dataclass(frozen=True)
class ActionResult:
    hotkey_name: str
    command: tuple[str, ...]
    returncode: int | None
    stdout: str
    stderr: str
    timed_out: bool = False
    error: str = ""


class ActionRunner:
    def __init__(self) -> None:
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="wolf-action")
        self._futures: set[Future[ActionResult]] = set()

    def submit(self, event: HotkeyEvent) -> None:
        self._drain_finished()

        hotkey = event.hotkey
        action = hotkey.action.strip()
        if not action:
            print(f"[wolf-hotkeyd] action {hotkey.name} skipped: no action configured", flush=True)
            return

        command = tuple(shlex.split(action))
        if not command:
            print(f"[wolf-hotkeyd] action {hotkey.name} skipped: empty action command", flush=True)
            return

        print(
            f"[wolf-hotkeyd] action {hotkey.name} starting: {action} "
            f"timeout={hotkey.action_timeout_seconds:.2f}s",
            flush=True,
        )
        future = self._executor.submit(_run_action, hotkey, command)
        future.add_done_callback(self._print_result)
        self._futures.add(future)

    def shutdown(self) -> None:
        self._executor.shutdown(wait=True, cancel_futures=False)

    def _drain_finished(self) -> None:
        self._futures = {future for future in self._futures if not future.done()}

    def _print_result(self, future: Future[ActionResult]) -> None:
        self._futures.discard(future)
        try:
            result = future.result()
        except Exception as exc:  # pragma: no cover - defensive callback guard
            print(f"[wolf-hotkeyd] action worker failed: {exc}", flush=True)
            return

        command = " ".join(shlex.quote(part) for part in result.command)
        if result.error:
            print(f"[wolf-hotkeyd] action {result.hotkey_name} failed to start: {result.error}", flush=True)
            return

        if result.timed_out:
            print(f"[wolf-hotkeyd] action {result.hotkey_name} timed out: {command}", flush=True)
        else:
            print(
                f"[wolf-hotkeyd] action {result.hotkey_name} exited code={result.returncode}: {command}",
                flush=True,
            )

        _print_stream(result.hotkey_name, "stdout", result.stdout)
        _print_stream(result.hotkey_name, "stderr", result.stderr)


def _run_action(hotkey: HotkeyConfig, command: tuple[str, ...]) -> ActionResult:
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=hotkey.action_timeout_seconds,
        )
    except subprocess.TimeoutExpired as exc:
        return ActionResult(
            hotkey_name=hotkey.name,
            command=command,
            returncode=None,
            stdout=exc.stdout or "",
            stderr=exc.stderr or "",
            timed_out=True,
        )
    except OSError as exc:
        return ActionResult(
            hotkey_name=hotkey.name,
            command=command,
            returncode=None,
            stdout="",
            stderr="",
            error=str(exc),
        )

    return ActionResult(
        hotkey_name=hotkey.name,
        command=command,
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def _print_stream(hotkey_name: str, stream_name: str, value: str) -> None:
    if not value:
        return

    for line in value.rstrip().splitlines():
        print(f"[wolf-hotkeyd] action {hotkey_name} {stream_name}: {line}", flush=True)
