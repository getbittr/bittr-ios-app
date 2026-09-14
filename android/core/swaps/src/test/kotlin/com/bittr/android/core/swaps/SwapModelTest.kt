package com.bittr.android.core.swaps

import java.io.File
import java.nio.file.Files
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SwapModelTest {

    private val full = Swap(
        dateId = "Swap lightning to onchain 20260914120000",
        direction = SwapDirection.LightningToOnchain,
        isSuggested = true,
        satoshisAmount = 50_000,
        privateKey = "ab".repeat(32),
        boltzId = "yes7P5Hn2FD5",
        boltzExpectedAmount = 50_561,
        onchainFees = 561,
        lightningFees = 555,
        feeHigh = 2.5,
        claimTransactionFee = 247,
        refundPublicKey = "03" + "55".repeat(32),
        claimLeafOutput = "82",
        refundLeafOutput = "20",
        claimPublicKey = "02" + "11".repeat(32),
        preimage = "5a".repeat(32),
        destinationAddress = "bcrt1qz2d3feqzlr3ggslt3ugs768utz8kmweah95qgv",
        boltzInvoice = "lnbcrt505610n1p…",
        lockupTx = "0100",
    )

    @Test
    fun `the swap file round-trips with iOS's keys`() {
        val json = SwapJson.encode(full)
        assertEquals(full, SwapJson.decode(json))
        val keys = Json.parseToJsonElement(json).jsonObject.keys
        assertTrue(keys.containsAll(listOf("dateID", "onchainToLightning", "boltzID", "sentOnchainTransactionID".takeIf { false } ?: "lockupTx", "claimTransactionFee")))
        assertFalse("absent values are left out", "createdInvoice" in keys)
    }

    @Test
    fun `an iOS swap file decodes`() {
        val ios = """{"dateID":"Swap onchain to lightning 20250101","onchainToLightning":true,"satoshisAmount":75000,"isSuggested":false,
            |"boltzID":"ChTExx2srRLT","boltzExpectedAmount":75352,"feeHigh":3,"onchainFees":423,"sentOnchainTransactionID":"aa"}""".trimMargin()
        val swap = SwapJson.decode(ios)!!
        assertEquals(SwapDirection.OnchainToLightning, swap.direction)
        assertEquals(75_352L, swap.boltzExpectedAmount)
        assertEquals(3.0, swap.feeHigh!!, 0.0)
        assertEquals("aa", swap.sentOnchainTransactionId)
        assertNull(SwapJson.decode("not json"))
    }

    @Test
    fun `lightning to onchain fees are a range, onchain to lightning a single figure`() {
        assertEquals(561L, full.definiteFees)
        assertEquals(562L, full.minimumTotalFees)
        assertEquals(1_116L, full.maximumTotalFees)
        assertEquals("562 - 1 116", full.formattedTotalFees())

        val submarine = Swap(direction = SwapDirection.OnchainToLightning, onchainFees = 400, lightningFees = 352)
        assertFalse(submarine.hasVariableFee)
        assertEquals("752", submarine.formattedTotalFees())
    }

    @Test
    fun `the swap file is named by sha256 of the Boltz id`() {
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Swap.hashedId(""))
    }

    @Test
    fun `sendable maxima follow iOS's formulas`() {
        // outbound 100 000: invoice ≤ 99 000, lockup ≤ 99 000 × 0.995 − 300 = 98 205, less claim fee 247.
        assertEquals(97_958L, SwapAmounts.maxLightningToOnchain(100_000, BoltzFeeQuote(0.5, 300), 247))
        // drainable 80 000 − 200 = 79 800 / 1.001 = 79 720.27 → 79 720 − 2, capped by channel space.
        assertEquals(79_718L, SwapAmounts.maxOnchainToLightning(80_000, BoltzFeeQuote(0.1, 200), 1_000_000))
        assertEquals(5_000L, SwapAmounts.maxOnchainToLightning(80_000, BoltzFeeQuote(0.1, 200), 5_000))
        assertEquals(0L, SwapAmounts.maxLightningToOnchain(0, null, 247))
        assertEquals(49_000L, SwapAmounts.availableChannelSpace(100_000, 50_000, 500, 500))
    }

    @Test
    fun `claim fee is fastest times 99, then the last known rate, then 50`() {
        assertEquals(247L, SwapAmounts.claimOrRefundFee(2.5, 9))
        assertEquals(891L, SwapAmounts.claimOrRefundFee(null, 9))
        assertEquals(4_950L, SwapAmounts.claimOrRefundFee(null, null))
    }

    @Test
    fun `statuses map to iOS's words, phases and markers`() {
        assertEquals(SwapCopy.STATUS_AWAITING_PAYMENT, BoltzStatus.userFriendly("transaction.confirmed", SwapDirection.OnchainToLightning))
        assertEquals(SwapCopy.STATUS_CLAIMING, BoltzStatus.userFriendly("transaction.confirmed", SwapDirection.LightningToOnchain))
        assertEquals(SwapCopy.STATUS_COMPLETE, BoltzStatus.userFriendly("invoice.settled", SwapDirection.LightningToOnchain))
        assertEquals("something.new", BoltzStatus.userFriendly("something.new", SwapDirection.LightningToOnchain))
        assertEquals(SwapPhase.Complete, BoltzStatus.phase("transaction.claimed"))
        assertEquals(SuggestedSwapStatus.Failed, BoltzStatus.suggestedMarker("transaction.refunded"))
        assertNull(BoltzStatus.suggestedMarker("transaction.mempool"))
        assertTrue(BoltzStatus.needsRefund("invoice.failedToPay"))
        assertEquals(SwapCopy.Q_GENERIC, BoltzStatus.answer(null, SwapDirection.OnchainToLightning))
    }

    @Test
    fun `the store keeps files by hashed id, the index, and the keyed caches`() {
        val directory = Files.createTempDirectory("swaps").toFile()
        val store = FileSwapStore(directory)

        store.save(full)
        assertTrue(File(directory, "${Swap.hashedId(full.boltzId!!)}.json").isFile)
        assertEquals(full, store.load(full.boltzId!!))
        assertEquals(full, store.loadForPushedId(Swap.hashedId(full.boltzId!!)))

        // A legacy file under the plaintext id still loads.
        File(directory, "legacyId.json").writeText(SwapJson.encode(full.copy(boltzId = "legacyId")))
        assertEquals("legacyId", store.load("legacyId")?.boltzId)

        assertEquals(1, store.nextSwapIndex())
        assertEquals(2, FileSwapStore(directory).nextSwapIndex())

        store.storeSwapId("date", "boltz")
        store.setSuggestedStatus("date", SuggestedSwapStatus.Pending)
        store.setSuggestedStatus("date", SuggestedSwapStatus.Succeeded)
        store.saveLatest(full)
        val reopened = FileSwapStore(directory)
        assertEquals("boltz", reopened.swapIdFor("date"))
        assertEquals(SuggestedSwapStatus.Succeeded, reopened.suggestedStatus("date"))
        assertEquals(full, reopened.latest())
        assertEquals(3, reopened.nextSwapIndex())
        reopened.saveLatest(null)
        assertNull(reopened.latest())
    }
}
