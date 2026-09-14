package com.bittr.android.core.wallet.seed

import com.bittr.android.core.wallet.SecureStore
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertTrue
import org.junit.Test

private class MapStore : SecureStore {
    private val values = mutableMapOf<String, ByteArray>()
    override fun read(key: String): ByteArray? = values[key]
    override fun write(key: String, value: ByteArray) {
        values[key] = value
    }
    override fun contains(key: String): Boolean = key in values
    override fun remove(key: String) {
        values.remove(key)
    }
}

/** Forwards to [Dispatchers.Default], counting how often work was sent to it. */
private class CountingDispatcher : CoroutineDispatcher() {
    val dispatches = AtomicInteger()
    override fun dispatch(context: CoroutineContext, block: Runnable) {
        dispatches.incrementAndGet()
        Dispatchers.Default.dispatch(context, block)
    }
}

/**
 * The PIN verifier is 120k rounds of PBKDF2, and every caller of [SeedWalletService] is a
 * view model on the main thread. Computed on the caller's dispatcher, the PIN pad's Confirm
 * tap froze the app long enough on a loaded emulator to raise "bittr isn't responding" —
 * the ANR trace had `SeedWalletService.derive` under `UnlockViewModel.submitPin` on `main`.
 */
class SeedWalletServiceDispatchTest {

    @Test
    fun `setting and checking the PIN derive the verifier on the derivation dispatcher`() = runTest {
        val derivation = CountingDispatcher()
        val service = SeedWalletService(MapStore(), derivation = derivation)

        service.createWallet()
        service.setPin("1234")
        val afterSetPin = derivation.dispatches.get()
        assertTrue("setPin derived on the caller's dispatcher", afterSetPin > 0)

        assertTrue("the right PIN should unlock", service.unlock("1234"))
        assertTrue("unlock derived on the caller's dispatcher", derivation.dispatches.get() > afterSetPin)
    }
}
