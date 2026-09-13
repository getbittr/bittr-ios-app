package com.bittr.android.core.wallet.ldk

import com.bittr.android.core.wallet.ldk.WalletSourceTree.modulePath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * This issue's Notes, as a test: *never mainnet keys, never production node
 * access, never real funds. Never commit seed material or node credentials.*
 *
 * Two of those four are already structurally impossible here — the module holds
 * no mainnet key material and opens no production account. The two that a single
 * line could still break are an embedded node id and an embedded endpoint, and
 * both are easy to add in good faith: iOS keeps them in `EnvironmentConfig`, and
 * a port that has not yet grown the Android equivalent is one `const val` away
 * from carrying a production LSP pubkey in a library module.
 *
 * That is why [NodeConfigPlan][com.bittr.android.core.wallet.ldk.node.NodeConfigPlan]
 * defaults no endpoint and takes an `LdkEnvironment` instead. This keeps it that
 * way.
 *
 * Scoped to `src/main`, so the tests can use test vectors freely — and they must,
 * since a config-parity test has to pass *something* in.
 */
class NoEmbeddedNodeCredentialsTest {

    private companion object {
        /**
         * A compressed secp256k1 public key as a hex literal: 66 characters
         * starting `02` or `03`. Node ids, and nothing else in this module,
         * look like that.
         *
         * Test vectors are excluded by scoping to `src/main`, not by
         * exempting anything — a *derived* xpub or pubkey in production code is
         * computed, not written down.
         */
        val NODE_ID = Regex("""["'](0[23][0-9a-fA-F]{64})["']""")

        /** Any http(s), ssl or tcp endpoint written into the source. */
        val ENDPOINT = Regex("""["'](?:https?|ssl|tcp)://[^"']+["']""")
    }

    @Test
    fun `no lightning node id is written into the wallet implementation`() {
        val offenders = WalletSourceTree.mainSources().flatMap { file ->
            NODE_ID.findAll(WalletSourceTree.codeOf(file))
                .map { "${file.modulePath()}: ${it.groupValues[1].take(12)}…" }
                .toList()
        }

        assertTrue(
            "A node id is hardcoded in this module. It belongs in the app's environment " +
                "configuration and reaches the wallet through LdkEnvironment — this issue's " +
                "notes are explicit that production node access is never committed, and a " +
                "library module is exactly where such a constant survives a build-flavour " +
                "change unnoticed.\n\n  " + offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `no chain source, gossip or LSP endpoint is written into the wallet implementation`() {
        val offenders = WalletSourceTree.mainSources().flatMap { file ->
            ENDPOINT.findAll(WalletSourceTree.codeOf(file))
                .map { "${file.modulePath()}: ${it.value}" }
                .toList()
        }

        assertTrue(
            "An endpoint is hardcoded in this module. Same reason as the node id: a " +
                "default that a test run or a misconfigured build can reach past is how " +
                "'never production node access' stops being true without anyone " +
                "deciding it.\n\n  " + offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the scan can see a string literal at all`() {
        // Both assertions above pass trivially against an empty scan. This
        // proves the regexes are being run over real source with real literals
        // in it, so a green result means "checked".
        assertTrue(
            "Found no quoted string in this module's sources — the scan is not reading " +
                "what it thinks it is.",
            WalletSourceTree.mainSources().any { Regex("""["'][^"']+["']""") in WalletSourceTree.codeOf(it) },
        )
    }
}
