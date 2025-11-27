# bittr iOS app

A non-custodial Bitcoin wallet for iOS that seamlessly integrates on-chain and Lightning Network payments, giving you full control over your Bitcoin.

## Overview

bittr is a self-custodial Bitcoin wallet that combines the power of on-chain Bitcoin transactions with instant Lightning Network payments. Built on top of [LDKNode](https://github.com/lightningdevkit/ldk-node) and [BDK](https://github.com/bitcoindevkit/bdk), the app provides a unified experience for managing your Bitcoin across both networks.

## Core Features

### 🔄 Unified Balance
View and manage both on-chain and Lightning payments in a single, unified balance. The app seamlessly handles funds across both networks, so you don't need to think about which network your Bitcoin is on.

### ⚡ Built-in Swaps
Instantly swap between on-chain Bitcoin and Lightning Bitcoin using integrated swap functionality powered by [Boltz](https://github.com/BoltzExchange/boltz-backend). Move funds between networks whenever you need to, without leaving the app.

### 🚀 Automatic Channel Opening
On your first Bitcoin purchase, the app automatically opens a Lightning channel for you. This means you can go from buying Bitcoin with fiat directly to being able to send and receive payments on the Bitcoin Lightning Network - no manual setup required.

### 🔐 Non-Custodial Control
Your keys, your Bitcoin. The app is fully non-custodial, meaning you maintain complete control over your funds. Your private keys are stored securely on your device, and you're the only one who can access your Bitcoin.

### 💰 Buy Bitcoin with Fiat
Purchase Bitcoin directly in the app via bank transfer. The app supports buying Bitcoin with EUR/CHF through IBAN transfers, making it easy to get started with Bitcoin.

### 📚 Built-in Bitcoin Education
Learn about Bitcoin through the integrated Academy feature, which provides educational content covering topics like what Bitcoin is, how the blockchain works, Lightning Network basics, and more.

### 📧 LNURL & Lightning Address Support
Send and receive Lightning payments using LNURL and Lightning Address (email format), making it easy to interact with the Lightning Network without needing to manage invoices manually.

## Technical Foundation

This app is built using:

- **[LDKNode](https://github.com/lightningdevkit/ldk-node)**: A ready-to-go Lightning node library that provides Lightning Network functionality out of the box. LDKNode combines the Lightning Development Kit (LDK) with Bitcoin Development Kit (BDK) to offer a complete Lightning node solution.

- **[BDK](https://github.com/bitcoindevkit/bdk)**: A modern, lightweight, descriptor-based Bitcoin wallet library written in Rust. BDK handles all on-chain Bitcoin wallet operations, including transaction creation, signing, and blockchain synchronization.

- **[Boltz](https://github.com/BoltzExchange/boltz-backend)**: A trustless and non-custodial swap service that enables seamless swaps between on-chain and Lightning Bitcoin. Boltz powers the built-in swap functionality in the app.

## Acknowledgments

We are deeply grateful to the developers and contributors of the open-source projects that make bittr possible:

- **LDKNode** ([GitHub](https://github.com/lightningdevkit/ldk-node)) - For providing a robust and developer-friendly Lightning node implementation
- **BDK** ([GitHub](https://github.com/bitcoindevkit/bdk)) - For creating a modern Bitcoin wallet library that simplifies wallet development
- **Boltz** ([GitHub](https://github.com/BoltzExchange/boltz-backend)) - For enabling trustless swaps between on-chain and Lightning Bitcoin
- **[Elias Rohrer (tnull)](https://github.com/tnull)** - For his helpful insights in implementing LDK and valuable feedback throughout the development process
- **[michael1011](https://github.com/michael1011)** - For his endless patience in helping us get Boltz swaps working in the bittr app
- **[Monday Wallet](https://github.com/reez/Monday)** - For serving as inspiration for much of our Bitcoin wallet implementation

Special thanks to all the contributors and maintainers of these projects for their dedication to building open-source infrastructure for the Bitcoin ecosystem.

---
