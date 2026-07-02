# Controller Mapping

Use debug mode to record the button names exposed by each controller mode.

```bash
wolf-hotkeyd --listen-debug
```

For contribution-quality captures, use the guided walkthrough:

```bash
/opt/wolf-hotkeyd/actions/capture-controller-input.sh "Controller layout name"
```

The walkthrough prompts for each expected control, records event output when
available, allows custom controls and manual notes, and prints GitHub issue
submission instructions when complete.

Expected buttons for the default recovery combo:

| Control | Common Linux input name |
|---|---|
| Start | `BTN_START` |
| Select / Back | `BTN_SELECT` |
| L1 | `BTN_TL` |
| R1 | `BTN_TR` |
| L3 | `BTN_THUMBL` |
| R3 | `BTN_THUMBR` |
| Guide / Home | varies; may be hidden by Steam Input |

If the expected controller is not listed, verify that `/dev/input` is mounted
inside the Steam container and that the daemon user can read the event devices.

## Wolf X-Box One Virtual Pad

Observed inside a Wolf Steam container from the virtual pad exposed as:

```text
Wolf X-Box One (virtual) pad
```

| Control | Event |
|---|---|
| A | `EV_KEY BTN_A,BTN_GAMEPAD,BTN_SOUTH` |
| B | `EV_KEY BTN_B,BTN_EAST` |
| X | `EV_KEY BTN_NORTH,BTN_X` |
| Y | `EV_KEY BTN_WEST,BTN_Y` |
| LB | `EV_KEY BTN_TL` |
| RB | `EV_KEY BTN_TR` |
| Minus / Select | `EV_KEY BTN_SELECT` |
| Plus / Start | `EV_KEY BTN_START` |
| Left stick press | `EV_KEY BTN_THUMBL` |
| Right stick press | `EV_KEY BTN_THUMBR` |
| LT | `EV_ABS ABS_Z value=255`, released at `0` |
| RT | `EV_ABS ABS_RZ value=255`, released at `0` |
| D-pad up | `EV_ABS ABS_HAT0Y value=-1`, released at `0` |
| D-pad down | `EV_ABS ABS_HAT0Y value=1`, released at `0` |
| D-pad left | `EV_ABS ABS_HAT0X value=-1`, released at `0` |
| D-pad right | `EV_ABS ABS_HAT0X value=1`, released at `0` |

Steam Deck back buttons may be mapped by Steam Input before reaching the Wolf
virtual pad. In the observed test, L4 emitted `BTN_A` and R4 emitted `BTN_X`
because those were the active Steam Input mappings.

Do not use `Minus / Select + Plus / Start + LB + RB` for daemon recovery. In the
observed Steam Deck plus Moonlight flow, that chord is already handled by
Wolf/Moonlight session control and removes the virtual input devices.

The recovery combo should avoid Start/Select and use controls confirmed as
normal `EV_KEY` events:

```text
LB + RB + left stick press + right stick press
BTN_TL + BTN_TR + BTN_THUMBL + BTN_THUMBR
```

## Reserved Upstream Shortcuts

Avoid controller chords that Moonlight clients may already reserve before input
reaches Wolf or the Steam container:

| Shortcut | Known use |
|---|---|
| Start + Select + L1 + R1 | Quit Moonlight streaming session |
| Start | Open Moonlight settings UI when not streaming |
| Start hold | Toggle Moonlight mouse mode |
| Start + Select | Emulate Mode on some Android gamepads |
| R1 + Start | Emulate Mode on some Android gamepads without Select |
| L1 + Start | Emulate Select on some Android gamepads |

Moonlight keyboard shortcuts also reserve `Ctrl+Alt+Shift` combinations for
stream control, including quit session, performance stats, mouse capture,
mouse mode, window mode, clipboard typing, minimizing, and cursor behavior.

Wolf does not currently document an additional user-facing controller hotkey
layer in its public quickstart/docs. Treat Wolf as the transport and virtual
input producer, then verify real behavior with the guided capture script for
the exact Moonlight client, controller, and Steam Input profile being used.

Steam and Steam Input add another reservation layer after the input reaches the
Steam container. Steam's global **Guide Button Chord Configuration** performs
actions while holding the controller's Guide/Steam/Home button. Valve documents
this as a special global layout for Guide-button chords, separate from Big
Picture and Desktop configurations.

Avoid `Guide`/`Steam`/`Home` based daemon combos. Depending on controller,
client, and Steam Input profile, these chords may be consumed by Steam before a
game sees them:

| Shortcut family | Common Steam / Steam Deck use |
|---|---|
| Guide / Steam button | Open Steam overlay, menu, or Big Picture focus |
| Guide + Start | Alt-Tab on Steam Controller chord layouts |
| Guide + Back / Select | Open on-screen keyboard on Steam Controller chord layouts |
| Guide + R1 | Screenshot on Steam Controller / Steam Deck style layouts |
| Guide + L1 | Magnifier on Steam Controller / Steam Deck style layouts |
| Guide + X | On-screen keyboard on Steam Deck |
| Guide + B long press | Force game shutdown on Steam Deck |
| Guide + L2 / R2 | Mouse clicks on Steam Controller / Steam Deck style layouts |
| Guide + right stick / trackpad | Mouse cursor on Steam Controller / Steam Deck style layouts |
| Guide + left stick up/down | Volume or brightness changes depending on platform/layout |
| Guide + Y | Turn off controller on Steam Controller chord layouts |

Steam Input can also add game-specific action sets, layers, and button chords.
A combo that is safe in one game profile can be consumed or remapped in another.
Prefer daemon combos that do not include Guide/Steam/Home, Start, Select/Back,
or Steam Deck rear buttons unless the guided capture proves they pass through
unchanged in the target profile.

References:

- Moonlight setup guide: https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
- Games on Whales Wolf quickstart: https://games-on-whales.github.io/wolf/stable/user/quickstart.html
- Batocera Moonlight shortcut summary: https://wiki.batocera.org/systems:moonlight
- Steamworks Steam Input player guide: https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_players
- Steam Controller community FAQ: https://www.reddit.com/r/SteamController/wiki/index/
