from __future__ import annotations

import time
from dataclasses import dataclass, field

from wolf_hotkeyd.config import HotkeyConfig


@dataclass(frozen=True)
class HotkeyEvent:
    kind: str
    hotkey: HotkeyConfig
    device_path: str
    device_name: str
    held_seconds: float = 0.0
    cooldown_remaining: float = 0.0


@dataclass
class DeviceHotkeyState:
    pressed: set[str] = field(default_factory=set)
    hold_started_at: dict[str, float] = field(default_factory=dict)
    fired_while_held: set[str] = field(default_factory=set)
    cooldown_logged: set[str] = field(default_factory=set)


class HotkeyEngine:
    def __init__(self, hotkeys: tuple[HotkeyConfig, ...]) -> None:
        self.hotkeys = hotkeys
        self._devices: dict[str, DeviceHotkeyState] = {}
        self._cooldown_until: dict[str, float] = {}

    def forget_device(self, device_path: str) -> None:
        self._devices.pop(device_path, None)

    def update_button(
        self,
        *,
        device_path: str,
        device_name: str,
        names: tuple[str, ...],
        pressed: bool,
        now: float | None = None,
    ) -> list[HotkeyEvent]:
        if now is None:
            now = time.monotonic()

        state = self._devices.setdefault(device_path, DeviceHotkeyState())
        normalized_names = {_normalize_button_name(name) for name in names}
        if pressed:
            state.pressed.update(normalized_names)
        else:
            state.pressed.difference_update(normalized_names)

        return self.evaluate_device(
            device_path=device_path,
            device_name=device_name,
            now=now,
        )

    def evaluate_device(
        self,
        *,
        device_path: str,
        device_name: str,
        now: float | None = None,
    ) -> list[HotkeyEvent]:
        if now is None:
            now = time.monotonic()

        state = self._devices.setdefault(device_path, DeviceHotkeyState())
        events: list[HotkeyEvent] = []

        for hotkey in self.hotkeys:
            required = {_normalize_button_name(button) for button in hotkey.buttons}
            if not required:
                continue

            hotkey_pressed = required.issubset(state.pressed)
            hold_started_at = state.hold_started_at.get(hotkey.name)

            if not hotkey_pressed:
                if hold_started_at is not None:
                    events.append(
                        HotkeyEvent(
                            kind="reset",
                            hotkey=hotkey,
                            device_path=device_path,
                            device_name=device_name,
                            held_seconds=now - hold_started_at,
                        )
                    )
                state.hold_started_at.pop(hotkey.name, None)
                state.fired_while_held.discard(hotkey.name)
                state.cooldown_logged.discard(hotkey.name)
                continue

            if hold_started_at is None:
                state.hold_started_at[hotkey.name] = now
                state.cooldown_logged.discard(hotkey.name)
                events.append(
                    HotkeyEvent(
                        kind="armed",
                        hotkey=hotkey,
                        device_path=device_path,
                        device_name=device_name,
                    )
                )
                continue

            held_seconds = now - hold_started_at
            if held_seconds < hotkey.hold_time_seconds:
                continue

            if hotkey.name in state.fired_while_held:
                continue

            cooldown_until = self._cooldown_until.get(hotkey.name, 0.0)
            if now < cooldown_until:
                if hotkey.name not in state.cooldown_logged:
                    state.cooldown_logged.add(hotkey.name)
                    events.append(
                        HotkeyEvent(
                            kind="cooldown",
                            hotkey=hotkey,
                            device_path=device_path,
                            device_name=device_name,
                            held_seconds=held_seconds,
                            cooldown_remaining=cooldown_until - now,
                        )
                )
                continue

            state.fired_while_held.add(hotkey.name)
            state.cooldown_logged.discard(hotkey.name)
            self._cooldown_until[hotkey.name] = now + hotkey.cooldown_seconds
            events.append(
                HotkeyEvent(
                    kind="triggered",
                    hotkey=hotkey,
                    device_path=device_path,
                    device_name=device_name,
                    held_seconds=held_seconds,
                )
            )

        return events


def _normalize_button_name(name: str) -> str:
    return name.strip().upper()
