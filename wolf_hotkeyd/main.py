from __future__ import annotations

import argparse
from pathlib import Path

from wolf_hotkeyd.actions import ActionRunner
from wolf_hotkeyd.config import DEFAULT_CONFIG_PATH, ConfigError, load_config
from wolf_hotkeyd.devices import (
    EvdevUnavailable,
    format_device,
    format_device_capabilities,
    list_devices,
    listen_debug,
    listen_hotkeys,
    matches_filter,
)
from wolf_hotkeyd.hotkeys import HotkeyEngine, HotkeyEvent


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="wolf-hotkeyd",
        description="Controller hotkey daemon for Wolf Steam containers.",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"YAML config path (default: {DEFAULT_CONFIG_PATH})",
    )
    parser.add_argument(
        "--list-devices",
        action="store_true",
        help="List visible /dev/input/event* devices and exit.",
    )
    parser.add_argument(
        "--listen-debug",
        action="store_true",
        help="Print EV_KEY and EV_ABS events from matching devices.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Detect configured hotkeys and log triggers without running actions.",
    )
    parser.add_argument(
        "--run-actions",
        action="store_true",
        help="Detect configured hotkeys and execute configured actions.",
    )
    parser.add_argument(
        "--raw-events",
        action="store_true",
        help="With --listen-debug, print non-key/non-axis event types too.",
    )
    parser.add_argument(
        "--include-sticks",
        action="store_true",
        help="With --listen-debug, include noisy analog stick axes.",
    )
    parser.add_argument(
        "--show-capabilities",
        action="store_true",
        help="With --list-devices, show advertised event capabilities.",
    )
    parser.add_argument(
        "--all-devices",
        action="store_true",
        help="Include keyboard/mouse/other input devices in debug listening.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if not args.list_devices and not args.listen_debug and not args.dry_run and not args.run_actions:
        parser.print_help()
        return 2

    if args.dry_run and args.run_actions:
        print("[wolf-hotkeyd] choose either --dry-run or --run-actions, not both")
        return 2

    try:
        config = load_config(args.config, allow_missing=args.config == DEFAULT_CONFIG_PATH)
    except ConfigError as exc:
        print(f"[wolf-hotkeyd] config error: {exc}")
        return 2

    try:
        if args.list_devices:
            devices = list_devices(config.devices, include_all=True)
            if not devices:
                print("[wolf-hotkeyd] no /dev/input/event* devices found")
            for device in devices:
                matched = "matched" if device.readable and matches_filter(device, config.devices) else "not-matched"
                print(f"[wolf-hotkeyd] {matched} {format_device(device)}")
                if args.show_capabilities and device.readable:
                    for line in format_device_capabilities(device.path):
                        print(f"[wolf-hotkeyd]   {line}")
            return 0

        if args.listen_debug:
            print("[wolf-hotkeyd] starting debug listener; press Ctrl+C to stop", flush=True)
            listen_debug(
                config.devices,
                include_all=args.all_devices,
                raw_events=args.raw_events,
                include_sticks=args.include_sticks,
                poll_interval=config.poll_interval,
                rescan_interval_seconds=config.rescan_interval_seconds,
            )

        if args.dry_run:
            if not config.hotkeys:
                print("[wolf-hotkeyd] no hotkeys configured")
                return 2
            print("[wolf-hotkeyd] starting dry-run hotkey listener; press Ctrl+C to stop", flush=True)
            _print_configured_hotkeys(config.hotkeys)
            listen_hotkeys(
                config.devices,
                HotkeyEngine(config.hotkeys),
                _print_hotkey_event,
                include_all=args.all_devices,
                poll_interval=config.poll_interval,
                rescan_interval_seconds=config.rescan_interval_seconds,
            )

        if args.run_actions:
            if not config.hotkeys:
                print("[wolf-hotkeyd] no hotkeys configured")
                return 2
            print("[wolf-hotkeyd] starting action hotkey listener; press Ctrl+C to stop", flush=True)
            _print_configured_hotkeys(config.hotkeys)
            runner = ActionRunner()

            def handle_event(event: HotkeyEvent) -> None:
                _print_hotkey_event(event, dry_run=False)
                if event.kind == "triggered":
                    runner.submit(event)

            try:
                listen_hotkeys(
                    config.devices,
                    HotkeyEngine(config.hotkeys),
                    handle_event,
                    include_all=args.all_devices,
                    poll_interval=config.poll_interval,
                    rescan_interval_seconds=config.rescan_interval_seconds,
                )
            finally:
                runner.shutdown()
    except EvdevUnavailable as exc:
        print(f"[wolf-hotkeyd] {exc}")
        return 1
    except KeyboardInterrupt:
        print("\n[wolf-hotkeyd] stopped")
        return 0

    return 0


def _print_configured_hotkeys(hotkeys: tuple) -> None:
    for hotkey in hotkeys:
        buttons = " + ".join(hotkey.buttons)
        print(
            f"[wolf-hotkeyd] configured hotkey {hotkey.name}: "
            f"{buttons} hold={hotkey.hold_time_seconds:.2f}s "
            f"cooldown={hotkey.cooldown_seconds:.2f}s",
            flush=True,
        )


def _print_hotkey_event(event: HotkeyEvent, *, dry_run: bool = True) -> None:
    prefix = f"[wolf-hotkeyd] hotkey {event.hotkey.name}"
    device = f"{event.device_path} {event.device_name}"

    if event.kind == "armed":
        print(f"{prefix} armed on {device}", flush=True)
        return

    if event.kind == "reset":
        print(f"{prefix} reset after {event.held_seconds:.2f}s on {device}", flush=True)
        return

    if event.kind == "cooldown":
        print(
            f"{prefix} held on {device} but cooldown has {event.cooldown_remaining:.2f}s remaining",
            flush=True,
        )
        return

    if event.kind == "triggered":
        action = event.hotkey.action or "<no action configured>"
        mode = "dry-run action" if dry_run else "action"
        print(
            f"{prefix} triggered after {event.held_seconds:.2f}s on {device}; {mode}={action}",
            flush=True,
        )
