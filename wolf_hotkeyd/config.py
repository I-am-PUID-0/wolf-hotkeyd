from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_CONFIG_PATH = Path("/etc/wolf-hotkeyd/config.yaml")


@dataclass(frozen=True)
class DeviceFilter:
    include: tuple[str, ...] = ("gamepad",)
    exclude: tuple[str, ...] = ()


@dataclass(frozen=True)
class HotkeyConfig:
    name: str
    description: str = ""
    buttons: tuple[str, ...] = ()
    hold_time_seconds: float = 2.0
    cooldown_seconds: float = 5.0
    action_timeout_seconds: float = 30.0
    action: str = ""


@dataclass(frozen=True)
class WolfHotkeyConfig:
    poll_interval: float = 0.05
    rescan_interval_seconds: float = 2.0
    devices: DeviceFilter = field(default_factory=DeviceFilter)
    hotkeys: tuple[HotkeyConfig, ...] = ()


class ConfigError(ValueError):
    """Raised when the wolf-hotkeyd config is invalid."""


def load_config(path: Path = DEFAULT_CONFIG_PATH, *, allow_missing: bool = True) -> WolfHotkeyConfig:
    if not path.exists():
        if allow_missing:
            return WolfHotkeyConfig()
        raise ConfigError(f"config file not found: {path}")

    try:
        import yaml
    except ImportError as exc:
        raise ConfigError("PyYAML is required to load config files") from exc

    with path.open("r", encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}

    if not isinstance(raw, dict):
        raise ConfigError("config root must be a mapping")

    return parse_config(raw)


def parse_config(raw: dict[str, Any]) -> WolfHotkeyConfig:
    devices_raw = raw.get("devices") or {}
    if not isinstance(devices_raw, dict):
        raise ConfigError("devices must be a mapping")

    hotkeys_raw = raw.get("hotkeys") or []
    if not isinstance(hotkeys_raw, list):
        raise ConfigError("hotkeys must be a list")

    return WolfHotkeyConfig(
        poll_interval=_positive_float(raw.get("poll_interval", 0.05), "poll_interval"),
        rescan_interval_seconds=_positive_float(
            raw.get("rescan_interval_seconds", 2.0),
            "rescan_interval_seconds",
        ),
        devices=DeviceFilter(
            include=_string_tuple(devices_raw.get("include", ("gamepad",)), "devices.include"),
            exclude=_string_tuple(devices_raw.get("exclude", ()), "devices.exclude"),
        ),
        hotkeys=tuple(_parse_hotkey(item, index) for index, item in enumerate(hotkeys_raw)),
    )


def _parse_hotkey(raw: Any, index: int) -> HotkeyConfig:
    if not isinstance(raw, dict):
        raise ConfigError(f"hotkeys[{index}] must be a mapping")

    name = str(raw.get("name") or "").strip()
    if not name:
        raise ConfigError(f"hotkeys[{index}].name is required")

    return HotkeyConfig(
        name=name,
        description=str(raw.get("description") or ""),
        buttons=tuple(button.upper() for button in _string_tuple(raw.get("buttons", ()), f"hotkeys[{index}].buttons")),
        hold_time_seconds=_positive_float(raw.get("hold_time_seconds", 2.0), f"hotkeys[{index}].hold_time_seconds"),
        cooldown_seconds=_positive_float(raw.get("cooldown_seconds", 5.0), f"hotkeys[{index}].cooldown_seconds"),
        action_timeout_seconds=_positive_float(
            raw.get("action_timeout_seconds", 30.0),
            f"hotkeys[{index}].action_timeout_seconds",
        ),
        action=str(raw.get("action") or ""),
    )


def _string_tuple(value: Any, field_name: str) -> tuple[str, ...]:
    if isinstance(value, str):
        return (value.strip(),)
    if not isinstance(value, list | tuple):
        raise ConfigError(f"{field_name} must be a string or list of strings")

    result = tuple(str(item).strip() for item in value if str(item).strip())
    return result


def _positive_float(value: Any, field_name: str) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise ConfigError(f"{field_name} must be a number") from exc

    if parsed <= 0:
        raise ConfigError(f"{field_name} must be greater than 0")
    return parsed
