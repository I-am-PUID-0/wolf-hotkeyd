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
