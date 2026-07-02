ARG BASE_IMAGE=ghcr.io/games-on-whales/steam:edge
FROM ${BASE_IMAGE}

USER root

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      python3 \
      python3-evdev \
      python3-yaml \
      procps && \
    rm -rf /var/lib/apt/lists/*

COPY wolf_hotkeyd /opt/wolf-hotkeyd/wolf_hotkeyd
COPY actions /opt/wolf-hotkeyd/actions
COPY examples /opt/wolf-hotkeyd/examples
COPY pyproject.toml README.md /opt/wolf-hotkeyd/
COPY deploy/steam-hotkeyd-image/99-wolf-hotkeyd.sh /etc/cont-init.d/99-wolf-hotkeyd.sh

RUN chmod +x /etc/cont-init.d/99-wolf-hotkeyd.sh /opt/wolf-hotkeyd/actions/*.sh
