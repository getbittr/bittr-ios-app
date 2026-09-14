package com.bittr.android.core.wallet.ldk.onchain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DescriptorXpubTest {

    /** The shape `Descriptor.newBip84` produces on a test network. */
    private val signetDescriptor =
        "wpkh([1a2b3c4d/84'/1'/0']tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2X" +
            "xWZJ7ZwDBiFZZ4y3z4tWqJ4cDNMhPKcRyRqh1bcpTzsJYLdKd/0/*)#gx7kqvj0"

    @Test
    fun `extracts the account xpub from a BIP84 descriptor`() {
        val xpub = DescriptorXpub.extract(signetDescriptor)
        assertEquals(
            "tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XxWZJ7ZwDBiFZZ4y3z4tW" +
                "qJ4cDNMhPKcRyRqh1bcpTzsJYLdKd",
            xpub,
        )
    }

    @Test
    fun `the derivation suffix and the checksum are not part of the xpub`() {
        val xpub = DescriptorXpub.extract(signetDescriptor)!!
        // This string is POSTed as `xpub_key` at signup
        // (Transfer2ViewController.swift:344-362), so a trailing "/0/*)#gx7kqvj0"
        // is an account the backend cannot match to its own wallet.
        assertEquals("no '/' may survive", -1, xpub.indexOf('/'))
        assertEquals("no checksum may survive", -1, xpub.indexOf('#'))
        assertEquals("no closing paren may survive", -1, xpub.indexOf(')'))
    }

    @Test
    fun `extracts a mainnet xpub the same way`() {
        val mainnet = "wpkh([1a2b3c4d/84'/0'/0']xpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg/0/*)#abcdefgh"
        assertEquals("xpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg", DescriptorXpub.extract(mainnet))
    }

    @Test
    fun `a descriptor with no key origin yields null rather than a wrong value`() {
        // iOS logs "Error: Descriptor format not recognized" and leaves `self.xpub`
        // unset; the wallet still starts. Failing soft is deliberate — see the
        // class comment.
        assertNull(DescriptorXpub.extract("wpkh(tpubDC8msFGeGuwnKG/0/*)#abcdefgh"))
        assertNull(DescriptorXpub.extract(""))
        assertNull(DescriptorXpub.extract("not a descriptor at all"))
    }

    @Test
    fun `an empty segment after the origin yields null, not an empty string`() {
        // `"...]".split("]")[1]` is "", and "" would travel all the way to the
        // signup request as a present-but-blank field — worse than an absent one,
        // because it looks like an answer.
        assertNull(DescriptorXpub.extract("wpkh([1a2b3c4d/84'/1'/0']"))
        assertNull(DescriptorXpub.extract("wpkh([1a2b3c4d/84'/1'/0']/0/*)"))
    }
}
