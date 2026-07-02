# Steam Runner Image

wolf-hotkeyd can be deployed by using a Steam runner image that extends the
standard Games on Whales Steam image with the daemon, action scripts, examples,
and Python dependencies preinstalled.

## Published GHCR Image

The public image is published to GitHub Container Registry:

```text
ghcr.io/i-am-puid-0/wolf-steam-hotkeyd
```

Use `latest` for the newest non-prerelease build:

```text
ghcr.io/i-am-puid-0/wolf-steam-hotkeyd:latest
```

Use a release tag for repeatable deployments:

```text
ghcr.io/i-am-puid-0/wolf-steam-hotkeyd:0.2.0
```

Use a `sha-*` tag when you want to pin an exact commit build:

```text
ghcr.io/i-am-puid-0/wolf-steam-hotkeyd:sha-98c8b9f
```

## Configure Wolf

Update the Steam app runner image in Wolf Den, Wolf UI, or the Wolf app
configuration from:

```text
ghcr.io/games-on-whales/steam:edge
```

to:

```text
ghcr.io/i-am-puid-0/wolf-steam-hotkeyd:latest
```

Start a new Steam session after changing the runner image. Existing containers
may need to be recreated before they use the new image.

## Verify A New Container

From the Docker/Wolf host:

```bash
docker exec "$CONTAINER" pgrep -af wolf_hotkeyd
docker exec "$CONTAINER" tail -n 80 /var/log/wolf-hotkeyd.log
```

Expected log shape:

```text
[wolf-hotkeyd] starting action hotkey listener; press Ctrl+C to stop
[wolf-hotkeyd] configured hotkey force_close_game: BTN_TL + BTN_TR + BTN_THUMBL + BTN_THUMBR hold=2.00s cooldown=5.00s
[wolf-hotkeyd] listening on /dev/input/event8 Wolf X-Box One (virtual) pad
```

## Disable Per Runner

Set this runner environment variable for games or profiles where the daemon
should not auto-start:

```text
WOLF_HOTKEYD_ENABLED=0
```

This is recommended for anti-cheat-protected multiplayer games.

## Local Image Build

Build locally when developing changes or when you want a private image:

```bash
docker build \
  -f deploy/steam-hotkeyd-image/Dockerfile \
  -t wolf-steam-hotkeyd:latest \
  .
```

Then configure the Steam runner image as:

```text
wolf-steam-hotkeyd:latest
```

## Release Tags

The Docker Image workflow publishes:

- `latest` for non-prerelease GitHub releases.
- The release version extracted from Release Please tags such as
  `wolf-hotkeyd-0.2.0` -> `0.2.0`.
- `sha-*` commit tags for exact build pinning.

For manual backfills, run the Docker Image workflow manually and provide:

```text
version: 0.2.0
latest: true
source_ref: wolf-hotkeyd-0.2.0
```
