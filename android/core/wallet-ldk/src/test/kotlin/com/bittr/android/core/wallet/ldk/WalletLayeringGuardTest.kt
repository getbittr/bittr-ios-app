package com.bittr.android.core.wallet.ldk

import com.bittr.android.core.wallet.ldk.WalletSourceTree.modulePath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The rule that makes every other test in this module possible.
 *
 * `build.gradle.kts` states it: everything that decides *what to do with the
 * user's funds* — the seed-import guard, the state discriminator, the quarantine
 * path, the blob classification, the node-start and retry decisions — is written
 * against `java.io.File` and injected interfaces, with no ldk-node, BDK or
 * Keystore type in its signature. Those types appear only in `adapter/`.
 *
 * That is not tidiness. `bdk-android` and `ldk-node-android` are UniFFI wrappers
 * over native `.so` files: a decision expressed in terms of them is provable only
 * on an emulator, and this module's definition of done is "each claim naming the
 * test that proves it". A claim whose test needs hardware CI does not have is a
 * claim with no test.
 *
 * **The rule was unenforced until now.** `build.gradle.kts` has been naming
 * `WalletLayeringGuardTest` as the thing that enforces it since the module was
 * created, and the class did not exist. That is the same failure shape as the
 * three Robolectric classes that stopped running inside a green build — a named
 * guarantee with nothing behind it — so it is fixed the same way, with a test
 * rather than by softening the comment.
 *
 * Adding a package: if it makes decisions, list it in [DECISION_PACKAGES]. If it
 * is an edge adapter, it belongs under `adapter/` and needs a reason.
 */
class WalletLayeringGuardTest {

    private companion object {
        /**
         * Packages that must stay provable on the JVM.
         *
         * `node/` is here for the same reason as the rest: its start gate,
         * retry schedule and config plan are the difference between one node
         * and two over the same channel state, and none of that should need an
         * emulator to check.
         *
         * `onchain/` is the BDK half, and it is the clearest case for the rule:
         * the drain clamp decides the largest amount that may leave the wallet,
         * and `BdkStore` recursively deletes a directory. Neither belongs behind
         * a native library that keeps its test off CI.
         *
         * `lightning/` is the ldk-node half and it is the largest of them. It
         * holds the arithmetic that turns `BalanceDetails` into the number on
         * the home screen, the guard that decides whether the wallet may be
         * deleted from the device — which is a decision about whether
         * force-close sweep material still matters — and the event pump's
         * acknowledgement order, which decides whether an event is replayed or
         * lost. Every one of those is a claim that would otherwise need a
         * funded regtest node to check.
         *
         * `host/` is the newest and the one whose membership is least obvious,
         * because it holds a `Service` and an `Intent` — Android types, which
         * this guard does not ban. It is listed because what it *decides* is
         * ordering: the process is held up before a start begins, a runner is
         * relaunched when its node is, and nothing erases key material while a
         * node is live. Every one of those is provable against fakes, and none
         * of them should stop being provable because someone reached for
         * `Node` to ask whether it is running.
         */
        val DECISION_PACKAGES =
            listOf("seed", "state", "bip", "node", "onchain", "lightning", "host")

        /** The only directory allowed to name a native binding. */
        const val ADAPTER_PACKAGE = "adapter"

        val NATIVE_PACKAGES = listOf(
            "org.lightningdevkit.ldknode",
            "org.bitcoindevkit",
        )
    }

    @Test
    fun `no decision package names a native binding`() {
        val offenders = WalletSourceTree.mainSources()
            .filter { file -> DECISION_PACKAGES.any { "/$it/" in file.modulePath().replace('\\', '/') } }
            .flatMap { file ->
                // Comments stripped: the KDoc in these files names ldk-node
                // types constantly, and it should — a rule written down nowhere
                // near the thing it constrains is a rule nobody finds.
                val code = WalletSourceTree.codeOf(file)
                NATIVE_PACKAGES.filter { it in code }
                    .map { "${file.modulePath()} references $it" }
            }

        assertTrue(
            "A fund-handling decision has taken a dependency on a native binding. Every " +
                "test covering that decision now needs an emulator to run, and this " +
                "module's definition of done is 'each claim naming the test that proves " +
                "it'. Move the binding-typed part into adapter/ and leave the decision " +
                "behind an interface.\n\n  " +
                offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the adapter package is the only place that does`() {
        val users = WalletSourceTree.mainSources()
            .filter { file ->
                val code = WalletSourceTree.codeOf(file)
                NATIVE_PACKAGES.any { it in code }
            }
            .map { it.modulePath().replace('\\', '/') }

        val strays = users.filterNot { "/$ADAPTER_PACKAGE/" in it }
        assertTrue(
            "Native bindings are referenced outside adapter/:\n  " + strays.joinToString("\n  "),
            strays.isEmpty(),
        )

        // A scan that finds nothing passes silently, and this one would find
        // nothing the day someone deletes the adapters. Assert it can see what
        // it is supposed to see.
        assertTrue(
            "Expected at least one adapter naming a native binding. If the adapters have " +
                "gone, this guard is checking an empty set and will keep passing.",
            users.isNotEmpty(),
        )
    }

    @Test
    fun `every decision package listed here exists`() {
        // The other half of the empty-set problem: a package renamed without
        // updating this list silently drops out of the guard.
        val paths = WalletSourceTree.mainSources().map { it.modulePath().replace('\\', '/') }
        val missing = DECISION_PACKAGES.filterNot { pkg -> paths.any { "/$pkg/" in it } }

        assertEquals(
            "These packages are named as decision layers but have no sources, so the " +
                "guard above is checking nothing for them: $missing",
            emptyList<String>(),
            missing,
        )
    }
}
