from __future__ import annotations

import glob
import select
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Iterator

from wolf_hotkeyd.config import DeviceFilter
from wolf_hotkeyd.hotkeys import HotkeyEngine, HotkeyEvent


EVENT_GLOB = "/dev/input/event*"
GAMEPAD_NAME_HINTS = (
    "8bitdo",
    "controller",
    "dualsense",
    "dualshock",
    "gamepad",
    "joy-con",
    "joystick",
    "nintendo",
    "pro controller",
    "steam controller",
    "wireless controller",
    "x-box",
    "xbox",
)
KEYBOARD_NAME_HINTS = ("keyboard",)
MOUSE_NAME_HINTS = ("mouse", "touchpad", "trackpad")


STICK_AXIS_NAMES = {"ABS_X", "ABS_Y", "ABS_RX", "ABS_RY"}


@dataclass(frozen=True)
class DeviceInfo:
    path: str
    name: str
    phys: str
    uniq: str
    vendor: int | None
    product: int | None
    bustype: int | None
    version: int | None
    is_gamepad: bool
    readable: bool
    error: str = ""


class EvdevUnavailable(RuntimeError):
    """Raised when the evdev dependency is not available."""


def iter_event_paths(pattern: str = EVENT_GLOB) -> list[str]:
    return sorted(glob.glob(pattern), key=_event_sort_key)


def list_devices(
    device_filter: DeviceFilter,
    *,
    include_all: bool = True,
    pattern: str = EVENT_GLOB,
) -> list[DeviceInfo]:
    evdev = _import_evdev()
    devices: list[DeviceInfo] = []

    for path in iter_event_paths(pattern):
        try:
            device = evdev.InputDevice(path)
            try:
                info = _device_info(device)
            finally:
                device.close()
        except OSError as exc:
            devices.append(
                DeviceInfo(
                    path=path,
                    name="",
                    phys="",
                    uniq="",
                    vendor=None,
                    product=None,
                    bustype=None,
                    version=None,
                    is_gamepad=False,
                    readable=False,
                    error=str(exc),
                )
            )
            continue

        if include_all or matches_filter(info, device_filter):
            devices.append(info)

    return devices


def listen_debug(
    device_filter: DeviceFilter,
    *,
    include_all: bool = False,
    raw_events: bool = False,
    include_sticks: bool = False,
    poll_interval: float = 0.05,
    rescan_interval_seconds: float = 2.0,
) -> None:
    evdev = _import_evdev()
    ecodes = evdev.ecodes
    open_devices: dict[str, object] = {}
    last_rescan = 0.0

    try:
        while True:
            now = time.monotonic()
            if now - last_rescan >= rescan_interval_seconds:
                _refresh_open_devices(evdev, open_devices, device_filter, include_all)
                last_rescan = now

            if not open_devices:
                time.sleep(max(poll_interval, 0.1))
                continue

            devices = list(open_devices.values())
            readable, _, errored = select.select(devices, [], devices, poll_interval)

            for device in errored:
                _close_device(open_devices, device)

            for device in readable:
                try:
                    for event in device.read():
                        debug_line = _format_debug_event(
                            ecodes,
                            device,
                            event,
                            raw_events=raw_events,
                            include_sticks=include_sticks,
                        )
                        if debug_line:
                            print(debug_line, flush=True)
                except OSError as exc:
                    print(
                        f"[wolf-hotkeyd] device disconnected: {getattr(device, 'path', '<unknown>')} ({exc})",
                        flush=True,
                    )
                    _close_device(open_devices, device)
    finally:
        for device in list(open_devices.values()):
            device.close()


def listen_hotkeys(
    device_filter: DeviceFilter,
    engine: HotkeyEngine,
    on_hotkey_event: Callable[[HotkeyEvent], None],
    *,
    include_all: bool = False,
    poll_interval: float = 0.05,
    rescan_interval_seconds: float = 2.0,
) -> None:
    evdev = _import_evdev()
    ecodes = evdev.ecodes
    open_devices: dict[str, object] = {}
    last_rescan = 0.0

    try:
        while True:
            now = time.monotonic()
            if now - last_rescan >= rescan_interval_seconds:
                removed_paths = _refresh_open_devices(evdev, open_devices, device_filter, include_all)
                for path in removed_paths:
                    engine.forget_device(path)
                last_rescan = now

            if not open_devices:
                time.sleep(max(poll_interval, 0.1))
                continue

            devices = list(open_devices.values())
            readable, _, errored = select.select(devices, [], devices, poll_interval)

            for device in errored:
                path = str(getattr(device, "path", ""))
                _close_device(open_devices, device)
                engine.forget_device(path)

            for device in readable:
                try:
                    for event in device.read():
                        button_update = _event_button_update(ecodes, event)
                        if button_update is None:
                            continue
                        names, pressed = button_update
                        for hotkey_event in engine.update_button(
                            device_path=device.path,
                            device_name=device.name,
                            names=names,
                            pressed=pressed,
                        ):
                            on_hotkey_event(hotkey_event)
                except OSError as exc:
                    print(
                        f"[wolf-hotkeyd] device disconnected: {getattr(device, 'path', '<unknown>')} ({exc})",
                        flush=True,
                    )
                    path = str(getattr(device, "path", ""))
                    _close_device(open_devices, device)
                    engine.forget_device(path)

            now = time.monotonic()
            for device in list(open_devices.values()):
                for hotkey_event in engine.evaluate_device(
                    device_path=device.path,
                    device_name=device.name,
                    now=now,
                ):
                    on_hotkey_event(hotkey_event)
    finally:
        for device in list(open_devices.values()):
            device.close()


def matches_filter(info: DeviceInfo, device_filter: DeviceFilter) -> bool:
    fields = (info.path, info.name, info.phys, info.uniq)
    haystack = " ".join(item.lower() for item in fields if item)

    if any(token.lower() in haystack for token in device_filter.exclude):
        return False

    include = tuple(token.lower() for token in device_filter.include)
    if not include:
        return True

    for token in include:
        if token == "gamepad" and info.is_gamepad:
            return True
        if token in haystack:
            return True

    return False


def format_device(info: DeviceInfo) -> str:
    if not info.readable:
        return f"{info.path} unreadable error={info.error}"

    ids = []
    if info.vendor is not None:
        ids.append(f"vendor=0x{info.vendor:04x}")
    if info.product is not None:
        ids.append(f"product=0x{info.product:04x}")

    role = "gamepad" if info.is_gamepad else "other"
    suffix = f" ({', '.join(ids)})" if ids else ""
    return f"{info.path} {role} name={info.name!r}{suffix}"


def format_device_capabilities(path: str) -> list[str]:
    evdev = _import_evdev()
    ecodes = evdev.ecodes

    device = evdev.InputDevice(path)
    try:
        capabilities = device.capabilities(verbose=False)
    finally:
        device.close()

    lines: list[str] = []
    for event_type in sorted(capabilities):
        if event_type == ecodes.EV_SYN:
            continue

        event_name = ",".join(code_names(ecodes.EV, event_type))
        code_map = _code_map_for_event_type(ecodes, event_type)
        parts = [
            _format_capability_value(code_map, event_type, value)
            for value in capabilities[event_type]
        ]
        lines.append(f"{event_name}: {', '.join(parts)}")

    return lines


def code_names(code_map: object, code: int) -> tuple[str, ...]:
    value = code_map.get(code, f"UNKNOWN_{code}")
    if isinstance(value, list | tuple):
        return tuple(str(item) for item in value)
    return (str(value),)


def _format_debug_event(
    ecodes: object,
    device: object,
    event: object,
    *,
    raw_events: bool,
    include_sticks: bool,
) -> str:
    if event.type == ecodes.EV_KEY:
        value = _key_value_name(event.value)
        names = code_names(_code_map_for_event_type(ecodes, event.type), event.code)
        return f"[wolf-hotkeyd] {device.path} {device.name} EV_KEY {','.join(names)} {value}"

    if event.type == ecodes.EV_ABS:
        names = code_names(_code_map_for_event_type(ecodes, event.type), event.code)
        if not include_sticks and _is_stick_axis(names):
            return ""
        return f"[wolf-hotkeyd] {device.path} {device.name} EV_ABS {','.join(names)} value={event.value}"

    if raw_events and event.type != ecodes.EV_SYN:
        event_names = code_names(ecodes.EV, event.type)
        code_map = _code_map_for_event_type(ecodes, event.type)
        names = code_names(code_map, event.code)
        return (
            f"[wolf-hotkeyd] {device.path} {device.name} "
            f"{','.join(event_names)} {','.join(names)} value={event.value}"
        )

    return ""


def _format_capability_value(code_map: object, event_type: int, value: object) -> str:
    evdev = _import_evdev()
    ecodes = evdev.ecodes

    if isinstance(value, tuple):
        code = int(value[0])
        details = value[1] if len(value) > 1 else None
    else:
        code = int(value)
        details = None

    name = ",".join(code_names(code_map, code))
    if event_type == ecodes.EV_ABS and details is not None:
        minimum = getattr(details, "min", None)
        maximum = getattr(details, "max", None)
        flat = getattr(details, "flat", None)
        fuzz = getattr(details, "fuzz", None)
        return f"{name}(min={minimum}, max={maximum}, flat={flat}, fuzz={fuzz})"

    return name


def _code_map_for_event_type(ecodes: object, event_type: int) -> object:
    return ecodes.bytype.get(event_type, {})


def _is_stick_axis(names: tuple[str, ...]) -> bool:
    return any(name in STICK_AXIS_NAMES for name in names)


def _event_button_update(ecodes: object, event: object) -> tuple[tuple[str, ...], bool] | None:
    if event.type != ecodes.EV_KEY:
        return None
    if event.value not in (0, 1):
        return None

    names = code_names(_code_map_for_event_type(ecodes, event.type), event.code)
    return names, event.value == 1


def _refresh_open_devices(
    evdev: object,
    open_devices: dict[str, object],
    device_filter: DeviceFilter,
    include_all: bool,
) -> list[str]:
    active_paths = set(iter_event_paths())
    removed_paths: list[str] = []

    for path, device in list(open_devices.items()):
        if path not in active_paths:
            print(f"[wolf-hotkeyd] device removed: {path}", flush=True)
            device.close()
            del open_devices[path]
            removed_paths.append(path)

    for path in active_paths:
        if path in open_devices:
            continue
        try:
            device = evdev.InputDevice(path)
            info = _device_info(device)
        except OSError as exc:
            print(f"[wolf-hotkeyd] cannot open {path}: {exc}", flush=True)
            continue

        if include_all or matches_filter(info, device_filter):
            open_devices[path] = device
            print(f"[wolf-hotkeyd] listening on {path} {device.name}", flush=True)
        else:
            device.close()

    return removed_paths


def _device_info(device: object) -> DeviceInfo:
    input_id = getattr(device, "info", None)
    return DeviceInfo(
        path=str(device.path),
        name=str(device.name or ""),
        phys=str(device.phys or ""),
        uniq=str(device.uniq or ""),
        vendor=getattr(input_id, "vendor", None),
        product=getattr(input_id, "product", None),
        bustype=getattr(input_id, "bustype", None),
        version=getattr(input_id, "version", None),
        is_gamepad=_looks_like_gamepad(device),
        readable=True,
    )


def _looks_like_gamepad(device: object) -> bool:
    evdev = _import_evdev()
    ecodes = evdev.ecodes
    name = str(device.name or "").lower()

    if any(hint in name for hint in KEYBOARD_NAME_HINTS + MOUSE_NAME_HINTS):
        return False
    if any(hint in name for hint in GAMEPAD_NAME_HINTS):
        return True

    try:
        capabilities = device.capabilities(verbose=False)
    except OSError:
        return False

    key_codes = set(_flatten_capability_codes(capabilities.get(ecodes.EV_KEY, ())))
    abs_codes = set(_flatten_capability_codes(capabilities.get(ecodes.EV_ABS, ())))

    gamepad_buttons = {
        ecodes.BTN_A,
        ecodes.BTN_B,
        ecodes.BTN_X,
        ecodes.BTN_Y,
        ecodes.BTN_TL,
        ecodes.BTN_TR,
        ecodes.BTN_SELECT,
        ecodes.BTN_START,
        ecodes.BTN_THUMBL,
        ecodes.BTN_THUMBR,
        ecodes.BTN_MODE,
        ecodes.BTN_GAMEPAD,
    }
    gamepad_axes = {
        ecodes.ABS_X,
        ecodes.ABS_Y,
        ecodes.ABS_RX,
        ecodes.ABS_RY,
        ecodes.ABS_HAT0X,
        ecodes.ABS_HAT0Y,
    }

    return bool(key_codes & gamepad_buttons) and bool(abs_codes & gamepad_axes)


def _flatten_capability_codes(values: Iterable[object]) -> Iterator[int]:
    for value in values:
        if isinstance(value, tuple):
            yield int(value[0])
        else:
            yield int(value)


def _close_device(open_devices: dict[str, object], device: object) -> None:
    path = str(getattr(device, "path", ""))
    if path in open_devices:
        del open_devices[path]
    device.close()


def _key_value_name(value: int) -> str:
    if value == 0:
        return "released"
    if value == 1:
        return "pressed"
    if value == 2:
        return "held"
    return f"value={value}"


def _event_sort_key(path: str) -> tuple[int, str]:
    name = Path(path).name
    try:
        return (int(name.removeprefix("event")), path)
    except ValueError:
        return (10**9, path)


def _import_evdev() -> object:
    try:
        import evdev
    except ImportError as exc:
        raise EvdevUnavailable(
            "evdev is required; inside the copied Wolf container tree run "
            "`/opt/wolf-hotkeyd/actions/install-container-deps.sh` first"
        ) from exc
    return evdev
