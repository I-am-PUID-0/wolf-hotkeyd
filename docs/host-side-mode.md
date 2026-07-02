# Host-Side Mode

Host-side mode runs the hotkey listener on the Docker/Wolf host instead of
inside the Steam game container.

This can reduce anti-cheat exposure because the Steam container no longer has a
resident Python process reading `/dev/input/event*`. The tradeoff is that the
host must be able to see the Wolf virtual controller device.

## Architecture

```text
Moonlight controller
  -> Wolf virtual input device on the host
  -> host wolf-hotkeyd listener
  -> host-force-close-game.sh
  -> docker exec into the active Wolf Steam container
  -> force-close-game.sh runs only at trigger time
```

The game container still sees a short-lived `bash`, `ps`, and `awk` process when
the recovery hotkey is triggered. For anti-cheat titles, this is lower exposure
than a resident input listener, but it is not a guarantee.

## Prerequisites

Install Python dependencies on the Docker/Wolf host:

```bash
python3 -m pip install 'evdev>=1.7,<2' 'PyYAML>=6,<7'
```

The host user running `wolf-hotkeyd` needs:

- read access to `/dev/input/event*`
- access to the Docker socket or Docker CLI
- the `wolf-hotkeyd` source tree available at the same path used in the config

## Validate Host Input Visibility

Start a Wolf Steam session, then run on the Docker/Wolf host:

```bash
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --list-devices \
  --show-capabilities
```

Look for a Wolf virtual gamepad, such as:

```text
Wolf X-Box One (virtual) pad
```

If the host cannot see the virtual gamepad, host-side mode cannot detect the
combo without a deeper Wolf integration.

## Dry-Run The Host Action

From the Docker/Wolf host:

```bash
/opt/wolf-hotkeyd/actions/host-force-close-game.sh --dry-run
```

By default the script selects the first running container named like
`WolfSteam_*`. Override selection when needed:

```bash
WOLF_HOTKEYD_CONTAINER=WolfSteam_example \
  /opt/wolf-hotkeyd/actions/host-force-close-game.sh --dry-run
```

or:

```bash
WOLF_HOTKEYD_CONTAINER_PREFIX=WolfSteam \
  /opt/wolf-hotkeyd/actions/host-force-close-game.sh --dry-run
```

## Run The Host-Side Daemon

```bash
PYTHONPATH=/opt/wolf-hotkeyd python3 -m wolf_hotkeyd \
  --config /opt/wolf-hotkeyd/examples/config.host.yaml \
  --run-actions
```

Hold the recovery combo:

```text
LB + RB + left stick press + right stick press
```

## Anti-Cheat Notes

Host-side mode is a mitigation, not a bypass or guarantee.

For anti-cheat-protected multiplayer games, the safest option remains a separate
Steam runner with `wolf-hotkeyd` disabled. Host-side mode is intended for cases
where you want recovery behavior with less resident tooling inside the game
container.
