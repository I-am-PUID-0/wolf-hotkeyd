# wolf-hotkeyd

`wolf-hotkeyd` is a small controller hotkey daemon for
[Games on Whales Wolf](https://github.com/games-on-whales/wolf) Steam runner
containers.

It listens to Linux input events from Wolf's virtual gamepad and can run a
configured recovery action when a controller chord is held. The included
recovery action is designed to close the active Steam/Proton game process while
leaving Steam Big Picture, Wolf, and the Moonlight stream alive.

## Features

- Lists and filters `/dev/input/event*` devices.
- Prints controller debug events for mapping buttons and axes.
- Detects multi-button controller hotkeys with hold time and cooldown.
- Supports dry-run mode before executing actions.
- Runs action scripts with timeout and captured stdout/stderr logging.
- Includes process-capture helpers for tuning game process selection.
- Includes a custom Steam runner image scaffold that auto-starts the daemon in
  each Wolf-created Steam container.

## Anti-Cheat Warning

`wolf-hotkeyd` reads `/dev/input/event*` and keeps a background process running
inside the Steam container. Some anti-cheat systems may classify any input
listener, process scanner, overlay, debugger, or helper daemon as suspicious.

Do not run this daemon in anti-cheat-protected multiplayer modes unless you are
comfortable with that risk. If a game warns about an input logger or suspicious
background process, treat `wolf-hotkeyd` as a likely contributor and disable it
for that game/container.

For the custom Steam image, disable auto-start with a runner environment
variable:

```text
WOLF_HOTKEYD_ENABLED=0
```

For anti-cheat titles, a conservative setup is to keep a separate Steam app
runner/image without `wolf-hotkeyd` enabled.

## Recovery Combo

The default recovery combo is:

```text
LB + RB + left stick press + right stick press
BTN_TL + BTN_TR + BTN_THUMBL + BTN_THUMBR
```

It is configured with a two-second hold and five-second cooldown.

Avoid using `Start + Select + LB + RB` for this daemon. In common
Moonlight/Wolf controller flows that chord may already be reserved for session
control and can remove the virtual input devices.

## Install For Development

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -e .
```

The daemon requires Linux input devices and the `evdev` package. It is expected
to run inside a Wolf Steam container with `/dev/input` mounted.

## Manual Container Install

Manual copying is useful while developing or debugging. Copy the project into a
Steam container at `/opt/wolf-hotkeyd`, then install container-side Python
dependencies once:

```bash
/opt/wolf-hotkeyd/actions/install-container-deps.sh
```

Run the copied tree with `PYTHONPATH`:

```bash
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd --list-devices
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd --listen-debug
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --config /opt/wolf-hotkeyd/examples/config.force-close.yaml \
  --run-actions
```

From the Docker host, avoid nested `docker cp` copies by clearing the old target
and copying the staged directory contents:

```bash
docker exec "$CONTAINER" rm -rf /opt/wolf-hotkeyd
docker exec "$CONTAINER" mkdir -p /opt/wolf-hotkeyd
docker cp /path/to/wolf-hotkeyd/. "$CONTAINER":/opt/wolf-hotkeyd/
```

If a copied path is missing, check for an accidental nested directory:

```bash
ls -lah /opt/wolf-hotkeyd
ls -lah /opt/wolf-hotkeyd/wolf-hotkeyd
```

## Automatic Steam Container Install

For normal use, build a custom Steam runner image so every new Steam container
created by Wolf already includes `wolf-hotkeyd` and its Python dependencies.

Build on the Docker host from the repository root:

```bash
docker build \
  -f deploy/steam-hotkeyd-image/Dockerfile \
  -t wolf-steam-hotkeyd:latest \
  .
```

Then update the Steam app runner image in Wolf Den, Wolf UI, or the Wolf app
configuration from:

```text
ghcr.io/games-on-whales/steam:edge
```

to:

```text
wolf-steam-hotkeyd:latest
```

The image uses the existing Games on Whales startup flow. During container init,
`/etc/cont-init.d/99-wolf-hotkeyd.sh` starts:

```bash
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --config /opt/wolf-hotkeyd/examples/config.force-close.yaml \
  --run-actions
```

Optional runner environment overrides:

```text
WOLF_HOTKEYD_ENABLED=0
WOLF_HOTKEYD_CONFIG=/opt/wolf-hotkeyd/examples/config.yaml
WOLF_HOTKEYD_LOG=/var/log/wolf-hotkeyd.log
```

Verify a newly launched Steam container:

```bash
docker exec "$CONTAINER" pgrep -af wolf_hotkeyd
docker exec "$CONTAINER" tail -n 80 /var/log/wolf-hotkeyd.log
```

If multiple Steam apps or profiles exist, update each Steam app runner image.

## CLI Usage

List visible input devices:

```bash
wolf-hotkeyd --list-devices
```

Show advertised capabilities for each event device:

```bash
wolf-hotkeyd --list-devices --show-capabilities
```

Listen for gamepad button and axis events:

```bash
wolf-hotkeyd --listen-debug
```

Include keyboard and mouse devices while debugging:

```bash
wolf-hotkeyd --listen-debug --all-devices
```

Show additional non-key/non-axis event types while debugging:

```bash
wolf-hotkeyd --listen-debug --all-devices --raw-events
```

Analog stick axes are suppressed by default because small resting drift can
produce a continuous stream. Include them only when deliberately mapping sticks:

```bash
wolf-hotkeyd --listen-debug --include-sticks
```

Detect configured hotkeys without running actions:

```bash
wolf-hotkeyd --config ./examples/config.yaml --dry-run
```

Run configured hotkey actions:

```bash
wolf-hotkeyd --config ./examples/config.yaml --run-actions
```

Run the force-close config:

```bash
wolf-hotkeyd --config ./examples/config.force-close.yaml --run-actions
```

## Container Notes

The Steam container needs read access to `/dev/input/event*`. Depending on the
container user and device permissions, this may require running as root, adding
the user to the input group, or adjusting the runner/device configuration.

Example volume/devices shape:

```yaml
services:
  steam:
    volumes:
      - /dev/input:/dev/input
    devices:
      - /dev/uinput:/dev/uinput
```

Debug from inside the container:

```bash
ls -lah /dev/input
cat /proc/bus/input/devices
/opt/wolf-hotkeyd/actions/install-container-deps.sh
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd --list-devices
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd --listen-debug
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --config /opt/wolf-hotkeyd/examples/config.yaml \
  --dry-run
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --config /opt/wolf-hotkeyd/examples/config.yaml \
  --run-actions
```

## Expected Debug Output

```text
[wolf-hotkeyd] listening on /dev/input/event7 8BitDo Ultimate 2C Wireless Controller
[wolf-hotkeyd] /dev/input/event7 8BitDo Ultimate 2C Wireless Controller EV_KEY BTN_START pressed
[wolf-hotkeyd] /dev/input/event7 8BitDo Ultimate 2C Wireless Controller EV_KEY BTN_SELECT pressed
[wolf-hotkeyd] /dev/input/event7 8BitDo Ultimate 2C Wireless Controller EV_ABS ABS_HAT0X value=-1
```

Use this output to confirm mappings for Start, Select, L1, R1, L3, R3, and
whether the Guide/Home button is visible inside the container. Some controls
that Steam treats like buttons may appear as `EV_ABS` axis events instead of
`EV_KEY` button events. Common examples are D-pad directions, analog triggers,
and sticks.

## Dry-Run Hotkey Test

Run:

```bash
wolf-hotkeyd --config ./examples/config.yaml --dry-run
```

Hold the recovery combo for two seconds. Expected output:

```text
[wolf-hotkeyd] hotkey force_close_game armed on /dev/input/event11 Wolf X-Box One (virtual) pad
[wolf-hotkeyd] hotkey force_close_game triggered after 2.01s on /dev/input/event11 Wolf X-Box One (virtual) pad; dry-run action=/opt/wolf-hotkeyd/actions/test-action.sh
```

## Action Test

The safe example config points at:

```text
/opt/wolf-hotkeyd/actions/test-action.sh
```

Run action mode, hold the same combo for two seconds, and expect output similar
to:

```text
[wolf-hotkeyd] hotkey force_close_game triggered after 2.01s on /dev/input/event11 Wolf X-Box One (virtual) pad; action=/opt/wolf-hotkeyd/actions/test-action.sh
[wolf-hotkeyd] action force_close_game starting: /opt/wolf-hotkeyd/actions/test-action.sh timeout=10.00s
[wolf-hotkeyd] action force_close_game exited code=0: /opt/wolf-hotkeyd/actions/test-action.sh
[wolf-hotkeyd] action force_close_game stdout: [test-action] wolf-hotkeyd action execution works
```

## Force-Close Test

Before enabling the real action, start a game and collect process evidence:

```bash
/opt/wolf-hotkeyd/actions/capture-game-processes.sh "Game Name"
/opt/wolf-hotkeyd/actions/debug-process-tree.sh
/opt/wolf-hotkeyd/actions/force-close-game.sh --dry-run
```

Review the selected candidate. It should be a game or game child process, not
Steam, `steamwebhelper`, `wineserver`, `services.exe`, `explorer.exe`, or
pressure-vessel helper processes.

The selector prints scored candidates and prefers game executables under Steam
library paths such as `steamapps/common` or `S:\common`, especially
Win64/shipping binaries. It penalizes Wine/Proton/system helpers such as
`steam.exe`, `winedevice.exe`, `svchost.exe`, `rpcss.exe`, `tabtip.exe`, and
pressure-vessel wrappers. It also penalizes crash-reporting/upload sidecars
such as `crs-handler.exe`, crash recorder processes, metrics uploaders, and
`CRS` helper directories so those do not outrank the main game executable.

After the dry-run candidate looks correct, run the force-close config:

```bash
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --config /opt/wolf-hotkeyd/examples/config.force-close.yaml \
  --run-actions
```

Hold the recovery combo for two seconds. The script sends `SIGTERM` to the
selected process tree, waits five seconds, then sends `SIGKILL` to any
surviving selected processes. Steam should remain running.

## Multi-Game Capture

Use this while testing additional games:

1. Start the game from Steam Big Picture.
2. Wait until the main menu or gameplay is loaded.
3. Run:

```bash
/opt/wolf-hotkeyd/actions/capture-game-processes.sh "Game Name"
```

The script writes a timestamped log under `/tmp/wolf-hotkeyd-captures/` by
default and prints the path. To store logs somewhere else:

```bash
WOLF_HOTKEYD_CAPTURE_DIR=/tmp/wolf-captures /opt/wolf-hotkeyd/actions/capture-game-processes.sh "Game Name"
```

Each capture includes input-device context, the Steam/Proton process tree, and a
`force-close-game.sh --dry-run` candidate selection. Send back the printed log
path or the file contents for any game where the selected PID does not look like
the real game process.

Retrieve captures from the Steam container with:

```bash
docker cp "$CONTAINER":/tmp/wolf-hotkeyd-captures ./wolf-hotkeyd-captures
```

## Controller Input Capture

Use this when mapping a new controller, testing Steam Input layouts, or
collecting evidence for missing/duplicated inputs:

```bash
/opt/wolf-hotkeyd/actions/capture-controller-input.sh "Steam Deck default layout"
```

The script prompts for:

- pre-capture notes
- whether to include all devices
- whether to include raw event types
- whether to include noisy stick axes
- capture duration
- post-capture notes

It writes a timestamped log under `/tmp/wolf-hotkeyd-input-captures/` by
default. To use a different directory or default duration:

```bash
WOLF_HOTKEYD_INPUT_CAPTURE_DIR=/tmp/controller-captures \
WOLF_HOTKEYD_INPUT_CAPTURE_SECONDS=60 \
/opt/wolf-hotkeyd/actions/capture-controller-input.sh "Steam Deck default layout"
```

Retrieve controller captures with:

```bash
docker cp "$CONTAINER":/tmp/wolf-hotkeyd-input-captures ./wolf-hotkeyd-input-captures
```
