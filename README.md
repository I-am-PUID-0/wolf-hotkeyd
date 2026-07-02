# wolf-hotkeyd

`wolf-hotkeyd` is a small Python companion daemon for Wolf Steam containers. It
starts with controller discovery and debug logging so controller button names can
be mapped before any recovery actions are wired in.

Phase 1 includes:

- YAML config loading with sensible defaults.
- `/dev/input/event*` discovery.
- Gamepad-oriented device filtering.
- `wolf-hotkeyd --list-devices`.
- `wolf-hotkeyd --listen-debug`.

Phase 2 includes dry-run hotkey detection:

- Per-device pressed-button tracking.
- Configured multi-button combos.
- Hold-time detection.
- Cooldown handling.
- Trigger logging without action execution.

Phase 3 adds action execution:

- `wolf-hotkeyd --run-actions`.
- Threaded script execution so input polling can continue.
- Timeout handling.
- Captured stdout/stderr/exit-code logging.

The sample config still runs only a harmless test action.

Phase 4 adds force-close helpers:

- `actions/capture-controller-input.sh` walks through controller input capture
  with notes.
- `actions/capture-game-processes.sh` collects repeatable per-game evidence.
- `actions/debug-process-tree.sh` captures Steam/Proton process evidence.
- `actions/force-close-game.sh --dry-run` shows the selected game candidate.
- `actions/force-close-game.sh` sends TERM, waits, then sends KILL to the
  selected process tree.
- `deploy/steam-hotkeyd-image/` builds a custom Steam runner image that starts
  the daemon automatically for every Wolf-created Steam container.
- `examples/config.force-close.yaml` is the opt-in hotkey config for the real
  force-close action.

## Install For Development

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -e .
```

The daemon requires Linux input devices and the `evdev` package. It is expected
to run inside a Wolf Steam container with `/dev/input` mounted.

## Copied Container Install

When the project is copied into a Wolf Steam container at `/opt/wolf-hotkeyd`,
install the container-side Python dependencies once per fresh container:

```bash
/opt/wolf-hotkeyd/actions/install-container-deps.sh
```

Then run the daemon with `PYTHONPATH` instead of the `wolf-hotkeyd` console
script:

```bash
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd --list-devices
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd --listen-debug
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --config /opt/wolf-hotkeyd/examples/config.force-close.yaml \
  --run-actions
```

From the TrueNAS host, avoid nested copies by clearing the old target and
copying the staged directory contents:

```bash
docker exec "$CONTAINER" rm -rf /opt/wolf-hotkeyd
docker exec "$CONTAINER" mkdir -p /opt/wolf-hotkeyd
docker cp /mnt/Storage_Pool/Docker/wolf-hotkeyd/. "$CONTAINER":/opt/wolf-hotkeyd/
```

If the path is missing after a copy, check for an accidental nested directory:

```bash
ls -lah /opt/wolf-hotkeyd
ls -lah /opt/wolf-hotkeyd/wolf-hotkeyd
```

## Automatic Steam Container Install

For normal use, build a custom Steam runner image so every new Steam container
created by Wolf already includes `wolf-hotkeyd` and its Python dependencies.

Build on the Docker host:

```bash
cd /mnt/Storage_Pool/Docker/wolf-hotkeyd
docker build \
  -f deploy/steam-hotkeyd-image/Dockerfile \
  -t wolf-steam-hotkeyd:latest \
  .
```

Then update the Steam app runner image in Wolf Den / Wolf UI from:

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

Confirmed behavior:

- A fresh Wolf Steam container using `wolf-steam-hotkeyd:latest` auto-started
  `python3 -m wolf_hotkeyd`.
- The daemon used `/opt/wolf-hotkeyd/examples/config.force-close.yaml`.
- It detected the Wolf virtual controller and listened on `/dev/input/event*`
  without a manual copy/install/run step.

## Usage

List visible input devices:

```bash
wolf-hotkeyd --list-devices
```

Listen for gamepad button and axis events:

```bash
wolf-hotkeyd --listen-debug
```

Use a custom config:

```bash
wolf-hotkeyd --config ./examples/config.yaml --listen-debug
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

Show advertised capabilities for each event device:

```bash
wolf-hotkeyd --list-devices --show-capabilities
```

Detect configured hotkeys without running actions:

```bash
wolf-hotkeyd --config ./examples/config.yaml --dry-run
```

Run configured hotkey actions:

```bash
wolf-hotkeyd --config ./examples/config.yaml --run-actions
```

Run the real force-close config:

```bash
wolf-hotkeyd --config ./examples/config.force-close.yaml --run-actions
```

## Container Notes

The Steam container needs read access to `/dev/input/event*`. Depending on the
container user and device permissions, this may require running as root, adding
the user to the input group, or adjusting the compose/device configuration.

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

The default recovery hotkey in `examples/config.yaml` is:

```text
BTN_TL + BTN_TR + BTN_THUMBL + BTN_THUMBR
```

On the observed Wolf virtual controller this maps to:

```text
LB + RB + left stick press + right stick press
```

Do not use `Plus / Start + Minus / Select + LB + RB` for the daemon. In the
observed Steam Deck plus Moonlight flow, that combo is already handled by
Wolf/Moonlight session control and removes the virtual input devices.

Hold the combo for two seconds while dry-run mode is active. Expected output:

```text
[wolf-hotkeyd] hotkey force_close_game armed on /dev/input/event11 Wolf X-Box One (virtual) pad
[wolf-hotkeyd] hotkey force_close_game triggered after 2.01s on /dev/input/event11 Wolf X-Box One (virtual) pad; dry-run action=/opt/wolf-hotkeyd/actions/test-action.sh
```

## Action Test

The example config points at a harmless test action:

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

The selector prints scored candidates and prefers game executables under
Steam library paths such as `steamapps/common` or `S:\common`, especially
Win64/shipping binaries. It penalizes Wine/Proton/system helpers such as
`steam.exe`, `winedevice.exe`, `svchost.exe`, `rpcss.exe`, `tabtip.exe`, and
pressure-vessel wrappers. It also penalizes crash-reporting/upload sidecars
such as `crs-handler.exe`, crash recorder processes, metrics uploaders, and
`CRS` helper directories so those do not outrank the main game executable.

After the dry-run candidate looks correct, run the opt-in force-close config:

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

Observed captures:

- Assetto Corsa Competizione selected the real Win64 shipping executable.
- Halo: The Master Chief Collection selected `MCC-Win64-Shipping.exe`.
- Horizon Zero Dawn Remastered initially selected a `CRS` crash-report helper;
  after adding crash/upload sidecar penalties, dry-run selected the main
  `HorizonZeroDawnRemastered.exe` process.

From the TrueNAS host, retrieve a capture from the Steam container with:

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

From the TrueNAS host, retrieve controller captures with:

```bash
docker cp "$CONTAINER":/tmp/wolf-hotkeyd-input-captures ./wolf-hotkeyd-input-captures
```
