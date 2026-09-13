# Blockstream's electrs, which is both of the two chain endpoints this network
# needs (BIT-132).
#
# WHY THIS IS BUILT AND NOT PULLED
#
# There are two projects called electrs and they are not interchangeable:
#
#   romanz/electrs        — Electrum protocol only. This is the one with popular
#                           third-party images (getumbrel/electrs and friends),
#                           and it has NO Esplora HTTP API, which is the half
#                           ldk-node needs on every network but mainnet.
#   Blockstream/electrs   — a fork that adds the Esplora REST API alongside the
#                           Electrum one. This is what esplora.blockstream.info
#                           runs. It publishes no first-party Docker image.
#
# So the choice is: pull the wrong project, pull an unpinnable third-party build
# of the right one, or build the right one from a git tag. A Dockerfile is the
# only one of the three whose bytes are the same tomorrow.
#
# COST, STATED RATHER THAN DISCOVERED
#
# A cold build is a full cargo release build — roughly 8-12 minutes and ~2 GB of
# intermediate artefacts. On the self-hosted runner it happens once and then
# never, because the image layer is cached locally. On a GitHub-hosted runner it
# happens every night, which is affordable for a nightly job and would not be for
# a per-push one; that is one of the reasons BIT-132 puts K7 and K8 in a nightly
# rather than into `wallet-instrumented`.

FROM rust:1.81-bookworm AS build

# Pinned to a tag, not a branch. `master` would make the bring-up's behaviour a
# function of the day it ran, which is the property a regtest harness exists to
# not have.
ARG ELECTRS_REF=v3.1.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        clang cmake libsnappy-dev git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${ELECTRS_REF}" \
        https://github.com/Blockstream/electrs.git . \
    && cargo build --release --bin electrs

FROM debian:bookworm-slim

# curl is not a convenience here: it is what the compose healthcheck runs, and a
# healthcheck that cannot execute reports `unhealthy` forever while the service
# is fine — which reads as a broken indexer.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsnappy1v5 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/target/release/electrs /usr/local/bin/electrs

RUN mkdir -p /electrs/db
ENV ELECTRS_DB_DIR=/electrs/db

# No ENTRYPOINT. The compose file passes the whole command line, including which
# addresses to listen on, because those are the values the rest of the network is
# wired to and they should be readable in one place.
