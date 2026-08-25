//
//  EvilBoltz.swift
//  bittr
//
//  ⚠️ DEBUG-ONLY TEST HARNESS ⚠️
//
//  Fault-injection for SEC-01 / SEC-02 (see SECURITY_REVIEW.md): simulates a
//  MALICIOUS Boltz server by tampering with swap-creation responses at the
//  exact point the app consumes them — i.e. precisely what a compromised
//  api.boltz.exchange (or a TLS MITM) could send. No changes to the regtest
//  backend are needed, and the same harness runs unchanged against a branch
//  that contains the fix (the tampering happens before any verification).
//
//  The public functions exist in ALL builds so the injection sites in
//  SwapManager need no conditional compilation, but every tampering code path
//  is `#if DEBUG` — in Release they are pure synchronous passthroughs and the
//  fault-injection machinery is compiled out entirely.
//
//  Modes (what gets tampered):
//
//    wrong-invoice   REVERSE swaps (lightning→onchain): the bolt11 invoice
//                    Boltz returns is replaced by a REAL regtest invoice from
//                    the e2e endpoint (staging.getbittr.com/api/e2e/invoice)
//                    with the SAME amount but a payment hash whose preimage
//                    only the "attacker" knows. Vulnerable app: pays the fake
//                    invoice, no onchain coins ever arrive → funds lost.
//                    Fixed app: detects invoice.paymentHash ≠ preimageHash and
//                    aborts before paying.
//
//    wrong-address   SUBMARINE swaps (onchain→lightning): the lockup `address`
//                    Boltz returns is replaced by an attacker-controlled
//                    address. Vulnerable app: sends the onchain lockup to the
//                    attacker; the invoice is never paid and the in-app refund
//                    path can never match → funds lost.
//                    Fixed app: re-derives the lockup script from the swap
//                    tree + keys and aborts before sending.
//
//    all             Both of the above.
//
//  How to enable (any ONE of these; launch argument wins over env var,
//  which wins over the baked-in default):
//
//    • The "bittr evil" app (recommended for Maestro): the shared
//      `bittr evil` scheme builds the Debug-EvilBoltz configuration —
//      bundle id com.bittr.bittr-evil, display name "bittr evil", mode
//      armed to `.all` via the EVIL_BOLTZ compilation condition. It installs
//      alongside "bittr regtest" and has its OWN keychain/wallet (SecureStore
//      scopes to the bundle id), so destructive tests never touch your normal
//      test wallet. Maestro:
//        - launchApp:
//            appId: com.bittr.bittr-evil
//      Control run (same app, harness disarmed):
//        - launchApp:
//            appId: com.bittr.bittr-evil
//            arguments: ["-evilBoltz", "off"]
//
//    • Xcode: Edit Scheme → Run → Arguments → Passed On Launch:
//        -evilBoltz wrong-invoice
//
//    • Terminal (simulator):
//        xcrun simctl launch --terminate-running-process booted \
//            com.bittr.bittr-regtest -evilBoltz wrong-address
//      or via environment variable:
//        SIMCTL_CHILD_BITTR_EVIL_BOLTZ=wrong-address \
//            xcrun simctl launch --terminate-running-process booted com.bittr.bittr-regtest
//
//    • Maestro (against the normal regtest app):
//        - launchApp:
//            appId: com.bittr.bittr-regtest
//            arguments: ["-evilBoltz", "wrong-invoice"]
//
//  Optional override for the attacker destination (default is the
//  deterministic address below — its key is documented at the bottom of this
//  file, so "stolen" regtest funds are recoverable):
//
//    SIMCTL_CHILD_BITTR_EVIL_BOLTZ_ADDRESS=bcrt1...   (env var)
//
//  Expected results:
//    • Current codebase (no fix): the swap proceeds with the tampered data —
//      for wrong-address, verify the regtest payment landed on the FAKE
//      address (e.g. https://esplora.bittr.io/address/<fake>); for
//      wrong-invoice, the invoice payment succeeds but no swap lockup ever
//      follows (swap sits pending; money is gone).
//    • Fix branch: swap creation aborts with an error BEFORE any payment is
//      made. No onchain tx (wrong-address) / no invoice payment
//      (wrong-invoice) happens at all.
//

import Foundation
#if DEBUG
import LightningDevKit
#endif

enum EvilBoltz {

    // MARK: - Public API (all builds; tampering paths are DEBUG-only)

    /// One-time launch banner so a mistyped flag is immediately visible in the
    /// console instead of silently testing nothing. No-op in Release.
    static func logStatus() {
        #if DEBUG
        let armed = mode
        if armed == .off {
            Log.info("EvilBoltz: OFF (enable with launch argument `-evilBoltz wrong-invoice|wrong-address|all`)")
        } else {
            Log.info("🚨🚨🚨 EVIL BOLTZ ACTIVE — mode: \(armed.rawValue). Swap responses will be tampered with to simulate a malicious Boltz server. Do not use real funds. 🚨🚨🚨")
        }
        #endif
    }

    /// Injection point: the `/swap/submarine` success handler in SwapManager,
    /// BEFORE the response is parsed/stored. Invokes `completion` with the
    /// tampered — or, when disarmed (always in Release), untouched — response.
    static func tamperSubmarineResponse(_ response: [String: Any], completion: ([String: Any]) -> Void) {
        #if DEBUG
        guard mode == .wrongAddress || mode == .all else {
            completion(response)
            return
        }
        guard response["error"] == nil,
              let originalAddress = response["address"] as? String else {
            completion(response)
            return
        }

        let fakeAddress = attackerAddress
        var tampered = response
        tampered["address"] = fakeAddress
        if let bip21 = response["bip21"] as? String {
            tampered["bip21"] = bip21.replacingOccurrences(of: originalAddress, with: fakeAddress)
        }

        Log.info("🚨 EVIL BOLTZ [submarine]: replaced lockup address. Original: \(originalAddress) → fake (attacker-controlled): \(fakeAddress). A vulnerable app will now send the user's onchain funds to the attacker; a fixed app must reject this response.")
        completion(tampered)
        #else
        completion(response)
        #endif
    }

    /// Injection point: the `/swap/reverse` success handler in SwapManager,
    /// BEFORE the response is parsed/stored. In DEBUG with an armed mode,
    /// fetches a real regtest invoice (same amount, attacker-known preimage)
    /// asynchronously and then invokes `completion` with the tampered
    /// response. When disarmed (always in Release) the completion runs
    /// synchronously with the untouched response.
    static func tamperReverseResponse(_ response: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        #if DEBUG
        guard mode == .wrongInvoice || mode == .all else {
            completion(response)
            return
        }
        guard response["error"] == nil,
              let originalInvoice = response["invoice"] as? String else {
            completion(response)
            return
        }

        Task {
            // Match the original invoice's amount so the fee display and all
            // downstream logic behave exactly as in a real swap. (0 = the
            // original was a zero-amount invoice, which the e2e endpoint
            // supports as well.)
            var amountSats = 0
            if let parsed = Bindings.Bolt11Invoice.fromStr(s: originalInvoice).getValue(),
               let msat = parsed.amountMilliSatoshis() {
                amountSats = Int(msat) / 1000
            }

            var tampered = response
            if let fakeInvoice = await fetchE2EInvoice(amountSats: amountSats) {
                tampered["invoice"] = fakeInvoice
                Log.info("🚨 EVIL BOLTZ [reverse]: replaced swap invoice (\(amountSats) sats). Original: \(originalInvoice) → fake (attacker-known preimage): \(fakeInvoice). A vulnerable app will pay this invoice and receive nothing; a fixed app must reject it (payment hash ≠ submitted preimage hash).")
            } else {
                Log.info("🚨 EVIL BOLTZ [reverse]: FAILED to fetch a fake invoice from the e2e endpoint — continuing with the UNTAMPERED response (test invalid, check staging.getbittr.com reachability).")
            }
            completion(tampered)
        }
        #else
        completion(response)
        #endif
    }

    #if DEBUG

    // MARK: - Mode selection (DEBUG only)

    enum Mode: String {
        case off
        case wrongInvoice = "wrong-invoice"
        case wrongAddress = "wrong-address"
        case all
    }

    /// The armed mode. Precedence: launch argument `-evilBoltz <mode>` >
    /// environment variable `BITTR_EVIL_BOLTZ=<mode>` > the `EVIL_BOLTZ`
    /// compilation condition (set by the Debug-EvilBoltz build configuration —
    /// the "bittr evil" app, which is therefore armed with `.all` out of the
    /// box) > off. A bare `-evilBoltz` with no value means `.all`;
    /// `-evilBoltz off` disarms even in the "bittr evil" app (control runs).
    /// Hard-disabled unless the build targets the development (regtest)
    /// environment — belt and suspenders on top of every tampering path
    /// being `#if DEBUG`.
    private static var mode: Mode {
        let selected: Mode
        if let index = CommandLine.arguments.firstIndex(of: "-evilBoltz") {
            let next = index + 1
            if CommandLine.arguments.indices.contains(next),
               !CommandLine.arguments[next].hasPrefix("-"),
               let parsed = Mode(rawValue: CommandLine.arguments[next]) {
                selected = parsed
            } else {
                selected = .all
            }
        } else if let raw = ProcessInfo.processInfo.environment["BITTR_EVIL_BOLTZ"],
                  let parsed = Mode(rawValue: raw) {
            selected = parsed
        } else {
            #if EVIL_BOLTZ
            selected = .all
            #else
            selected = .off
            #endif
        }
        guard EnvironmentConfig.isDevelopment else { return .off }
        return selected
    }

    // MARK: - Attacker identity (DEBUG only)

    /// The address "stolen" funds are sent to in `wrong-address` mode.
    /// Override with the `BITTR_EVIL_BOLTZ_ADDRESS` environment variable (e.g.
    /// to an address of your regtest backend's wallet so you can watch the
    /// theft land). Must be a valid regtest address or the send fails before
    /// broadcast.
    private static var attackerAddress: String {
        if let override = ProcessInfo.processInfo.environment["BITTR_EVIL_BOLTZ_ADDRESS"],
           !override.isEmpty {
            return override
        }
        return Self.defaultAttackerAddress
    }

    /// Deterministic throwaway regtest P2TR address.
    ///
    /// internal key  = SHA256("bittr-evil-boltz-attacker-key") mod n (even-y)
    /// output key    = BIP341 TapTweak of the internal key, no script tree
    /// private key   = 80878d29f2e8642578384393447a741c318b17a5e066616557bef7b50bc79321
    ///
    /// The key is published here on purpose: anyone can import it into a
    /// regtest wallet (or use it with the taproot tweak) to inspect/sweep the
    /// "stolen" funds after a successful demonstration. NEVER send real funds
    /// to this address.
    private static let defaultAttackerAddress = "bcrt1pcz9mae53csyv8d0t4fansh446jdjey2pg2djn5utqver5e42gp5s507k3j"

    // MARK: - Fake invoice source (DEBUG only)

    /// Requests a fresh regtest invoice from the bittr e2e endpoint — the same
    /// one the Maestro flows use (shared/flows/scripts/request_invoice.js).
    /// The invoice is real and settles normally; its preimage is known only to
    /// the e2e service (our "attacker"), NOT to the app — which is exactly the
    /// SEC-01 theft scenario.
    private static func fetchE2EInvoice(amountSats: Int) async -> String? {
        guard let url = URL(string: "\(EnvironmentConfig.bittrAPIBaseURL)/e2e/invoice") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: CallsManager.defaultTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "amount_in_sats": amountSats,
            "memo": "EvilBoltz test harness"
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Accept whichever field the endpoint uses (mirrors request_invoice.js).
        return (json["invoice"] ?? json["bolt11"] ?? json["payment_request"] ?? json["pr"]) as? String
    }

    #endif
}
