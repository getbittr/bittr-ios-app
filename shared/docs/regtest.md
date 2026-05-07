# Regtest environment

Setup for the deterministic test environment driving Maestro flows on both platforms.

To document: how the regtest environment that's already running locally is configured, so it's reproducible and reusable for Android development.

## Suggested sections (fill in)

- **Components**: bitcoind / electrs / LDK Node peer / Boltz testnet wiring.
- **Bring-up**: commands to start the stack from a clean state.
- **Fixture seeding**: scripts to put wallets into known states (empty / synced / pending / channel open / settled swap / IBAN registered).
- **Reset**: how to wipe state between runs.
- **Connection details**: how the iOS app and (later) Android app point at the local stack — env vars, build configuration.
- **Boltz**: testnet endpoint config, since regtest Boltz is harder to host.
