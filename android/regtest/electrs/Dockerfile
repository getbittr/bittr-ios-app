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
# of the right one, or build the right one from source. A Dockerfile is the only
# one of the three whose bytes are the same tomorrow.
#
# AND IT CANNOT BE BUILT FROM A TAG — THE PROJECT PUBLISHES NONE THAT WOULD WORK
#
# This file used to say "from a git tag", pinned at `v3.1.0`. No such tag exists.
# The first run this network was ever asked for died in 53 seconds on the clone,
# and it could never have done anything else — the pin was unreachable on every
# runner, so this was not a CI-environment failure.
#
# The deeper problem is that no tag would have worked. Blockstream/electrs
# carries exactly five, `v0.1.0` through `v0.4.1`, and every one of them is
# INHERITED FROM romanz/electrs — `v0.4.1` is a 2018 commit that predates the
# fork. Checked rather than assumed: that tree has no `src/rest.rs`, no
# `src/new_index/`, and not one occurrence of `esplora`. It is the Electrum-only
# project this comment opens by warning against, wearing the right repo's URL.
#
# So "pin a tag" is unsatisfiable here, not merely unsatisfied. The Esplora API
# ships on the `new-index` branch, which is the repository's default branch.
#
# Pinning a COMMIT is the better form of the original intent anyway. The intent
# was "the bring-up's behaviour is not a function of the day it ran", and a
# branch name fails that. A tag would too, more quietly, since a tag can be moved
# and a SHA cannot.
#
# COST, STATED RATHER THAN DISCOVERED
#
# A cold build is a full cargo release build — roughly 8-12 minutes and ~2 GB of
# intermediate artefacts. On the self-hosted runner it happens once and then
# never, because the image layer is cached locally. On a GitHub-hosted runner it
# happens every night, which is affordable for a nightly job and would not be for
# a per-push one; that is one of the reasons BIT-132 puts K7 and K8 in a nightly
# rather than into `wallet-instrumented`.

# Matches the `channel` in electrs's own rust-toolchain.toml at the commit below.
# Not cosmetic: rustup reads that file and would otherwise download the pinned
# toolchain on every cold build, so a mismatched base image silently pays for two
# toolchains and makes the version in this line a decoration rather than a fact.
FROM rust:1.92-bookworm AS build

# A commit on `new-index`, not a tag — see the header for why no tag can work.
# This is the branch tip as of 2026-09-08 ("Merge pull request #258 from
# agoodminute/fix/cap-checkpoint-merkle-proof-concurrency").
#
# Verified against this exact tree rather than assumed, because the last pin here
# was never resolved at all:
#   - `src/rest.rs` exists, and routes `GET /blocks/tip/height` at rest.rs:772 —
#     which is the URL the compose healthcheck curls, so an unhealthy electrs
#     means the indexer, not a missing route.
#   - All nine flags docker-compose.yml passes are accepted by src/config.rs:
#     --network --daemon-dir --daemon-rpc-addr --cookie --db-dir --http-addr
#     --electrum-rpc-addr --cors --jsonrpc-import.
#
# To move it: pick a commit on `new-index`, re-check those two things, and bump
# the base image if rust-toolchain.toml moved.
ARG ELECTRS_REF=4b1a0186b12ae3e0ef6697a547d53f3a93d9c66b

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        clang cmake libsnappy-dev git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
# `git clone --branch` takes a branch or tag name and NOT a commit, so pinning a
# SHA means fetching it directly. Still a depth-1 fetch: one commit, no history.
RUN git init -q . \
    && git remote add origin https://github.com/Blockstream/electrs.git \
    && git fetch -q --depth 1 origin "${ELECTRS_REF}" \
    && git checkout -q FETCH_HEAD \
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
