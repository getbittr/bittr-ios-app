package com.bittr.android.core.wallet.ldk.bip

import fr.acinq.bitcoin.Bitcoin
import fr.acinq.bitcoin.Block
import fr.acinq.bitcoin.ByteVector64
import fr.acinq.bitcoin.Crypto
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RegistrationSignerTest {

    /** The BIP-84 test vector phrase; its first mainnet receive address is published in BIP-84. */
    private val phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    @Test
    fun `signs with the key of the first receive address`() {
        val signer = RegistrationSigner(mnemonic = { phrase }, mainnet = true)
        val message = "I confirm I'm the sole owner of the bitcoin address I provided and I will be sending my own funds to bittr. Order: abc. IBAN: NL27ABNA0451135725"

        val decoded = Base64.getDecoder().decode(signer.sign(message))
        val recovered = Crypto.recoverPublicKey(
            ByteVector64(decoded.copyOfRange(1, 65)),
            BitcoinMessageSigner.messageDigest(message),
            decoded[0] - 27 - 12,
        )

        assertEquals("m/84'/0'/0'/0/0", signer.path)
        assertEquals(
            "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
            Bitcoin.computeBIP84Address(recovered, Block.LivenetGenesisBlock.hash),
        )
    }

    @Test
    fun `development builds sign on coin type 1 and no seed signs nothing`() {
        assertEquals("m/84'/1'/0'/0/0", RegistrationSigner(mnemonic = { phrase }, mainnet = false).path)
        assertNull(RegistrationSigner(mnemonic = { null }, mainnet = false).sign("x"))
    }
}
