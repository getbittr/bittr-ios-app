package com.bittr.android.core.common.destination

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The four shapes a scanned or pasted string can take, pinned against
 * `AddressParsing.swift:15`.
 *
 * ## Where the vectors come from
 *
 * Addresses are either **published BIP-173/BIP-350 test vectors** or minted with the
 * BIP's own reference implementation. They are not minted with the code under test —
 * that would only prove it agrees with itself. The LNURL in
 * [a published LNURL decodes to its documented URL] is the LUD-01 example, whose
 * expected plaintext is documented in the spec; it decoding to exactly that URL is
 * what says the bech32 layer underneath all of this is right.
 *
 * Regtest is the network under test throughout, because regtest is what the debug
 * build — the one Maestro installs — is configured for.
 */
class DestinationParserTest {

    private val network = BitcoinNetwork.REGTEST

    // Minted with the BIP-173 reference implementation from SHA-256("bittr-bit100").
    private val regtestP2wpkh = "bcrt1qt8t4ycw8eld5taqqh2ug7mhq3pwu3dpvxl25fw"
    private val regtestP2pkh = "mohzNwwxGJXrgyFxUdTrVfopf4sxzUNkUE"
    private val mainnetP2wpkh = "bc1qt8t4ycw8eld5taqqh2ug7mhq3pwu3dpvwsg295"

    // HRP `lnbcrt1500n` = 1500 nano-BTC = 150 sats; `lnbcrt2500u` = 250 000 sats.
    private val invoice150Sats =
        "lnbcrt1500n1qqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydpk8qarc0jqgfzyvjz2f389q5" +
            "j52ev95hz7vp3xgengdfkxuurjw3m8s7nu06qg9pyx3z9ger5sj22fdxy6nj0dnuknp"
    private val invoiceNoAmount =
        "lnbcrt1qqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydpk8qarc0jqgfzyvjz2f389q5j52ev" +
            "95hz7vp3xgengdfkxuurjw3m8s7nu06qg9pyx3z9ger5sj22fdxy6nj0fh80d0"

    // ------------------------------------------------------------------
    // Shape 1 — a bare on-chain address
    // ------------------------------------------------------------------

    @Test
    fun `a bare segwit address is an on-chain destination with no amount`() {
        assertEquals(
            Destination.OnChain(regtestP2wpkh, amountSats = null),
            DestinationParser.parse(regtestP2wpkh, network),
        )
    }

    @Test
    fun `a bare legacy address is an on-chain destination`() {
        assertEquals(
            Destination.OnChain(regtestP2pkh, amountSats = null),
            DestinationParser.parse(regtestP2pkh, network),
        )
    }

    @Test
    fun `an address scanned in upper case comes back lower-cased`() {
        // QR encoders prefer upper case — alphanumeric mode packs denser — so this is
        // the common scan, not the exotic one. Case is meaningless in bech32, so
        // normalising here means one canonical form reaches Send.
        assertEquals(
            Destination.OnChain(regtestP2wpkh),
            DestinationParser.parse(regtestP2wpkh.uppercase(), network),
        )
    }

    @Test
    fun `one wrong character is not an address`() {
        // The reason the checksum is ported rather than a prefix test: this string
        // differs from a real address by a single character, and paying it would
        // burn the money. `bcrt1…` prefix matching would accept it.
        val corrupted = "bcrt1qt8t4ycw8eld5taqqh2ug7mhq3pwu3dpvxl25qw"
        assertEquals(Destination.Unrecognised, DestinationParser.parse(corrupted, network))
    }

    @Test
    fun `an address for another chain is not accepted`() {
        // A mainnet address in the regtest build parses as perfectly good bech32. Only
        // the HRP says it would never confirm, so only the HRP can reject it.
        assertEquals(Destination.Unrecognised, DestinationParser.parse(mainnetP2wpkh, network))
        assertEquals(
            Destination.OnChain(mainnetP2wpkh),
            DestinationParser.parse(mainnetP2wpkh, BitcoinNetwork.MAINNET),
        )
    }

    @Test
    fun `a taproot address is accepted, and only with a bech32m checksum`() {
        // BIP-350's footgun: witness v0 carries a bech32 checksum and v1+ carries a
        // bech32m one. An implementation that accepts either for either will pass every
        // happy-path test and still wave through a corrupted taproot address.
        val taproot = "bcrt1pa7kp7mexm7ql80p8lkqnrf0473j8j7ss973untdsv3gdwud58wlq6dt4cg"
        assertEquals(Destination.OnChain(taproot), DestinationParser.parse(taproot, network))

        // The same witness program, checksummed as bech32 instead of bech32m.
        val wrongConstant = "bcrt1pa7kp7mexm7ql80p8lkqnrf0473j8j7ss973untdsv3gdwud58wlq03mea2"
        assertEquals(Destination.Unrecognised, DestinationParser.parse(wrongConstant, network))
    }

    @Test
    fun `a v0 address checksummed as bech32m is rejected`() {
        // The other direction of the same pairing.
        val wrongConstant = "bcrt1qt8t4ycw8eld5taqqh2ug7mhq3pwu3dpvnr6cvv"
        assertEquals(Destination.Unrecognised, DestinationParser.parse(wrongConstant, network))
    }

    @Test
    fun `a 32-byte v0 address is accepted as P2WSH`() {
        val p2wsh = "bcrt1qa7kp7mexm7ql80p8lkqnrf0473j8j7ss973untdsv3gdwud58wlqs6tuq5"
        assertEquals(Destination.OnChain(p2wsh), DestinationParser.parse(p2wsh, network))
    }

    @Test
    fun `a mixed-case bech32 address is rejected`() {
        // BIP-173 forbids it, and it is how a checksum gets defeated by a string that
        // "looks like" it round-trips.
        val mixed = "BCRT1qt8t4ycw8eld5taqqh2ug7mhq3pwu3dpvxl25fw"
        assertEquals(Destination.Unrecognised, DestinationParser.parse(mixed, network))
    }

    // ------------------------------------------------------------------
    // Shape 2 — a BIP-21 URI carrying an amount
    // ------------------------------------------------------------------

    @Test
    fun `a BIP-21 URI yields the address and the amount in sats`() {
        val uri = "bitcoin:$regtestP2wpkh?amount=0.0015"
        assertEquals(
            Destination.OnChain(regtestP2wpkh, amountSats = 150_000L),
            DestinationParser.parse(uri, network),
        )
    }

    @Test
    fun `a BIP-21 amount is BTC, and one sat survives the conversion`() {
        // `amount=` is denominated in BTC, so the smallest legal value is 1e-8. Done in
        // BigDecimal precisely so this comes back as 1 and not 0.
        val uri = "bitcoin:$regtestP2wpkh?amount=0.00000001"
        assertEquals(
            Destination.OnChain(regtestP2wpkh, amountSats = 1L),
            DestinationParser.parse(uri, network),
        )
    }

    @Test
    fun `a zero amount is the same as no amount`() {
        // iOS: `if let amount, amount != 0` (AddressParsing.swift:66). A zero here must
        // leave the amount field empty rather than prefill it with 0.
        val uri = "bitcoin:$regtestP2wpkh?amount=0"
        assertNull((DestinationParser.parse(uri, network) as Destination.OnChain).amountSats)
    }

    @Test
    fun `other BIP-21 parameters do not disturb the address or the amount`() {
        val uri = "bitcoin:$regtestP2wpkh?amount=0.0015&label=Bittr&message=thanks"
        assertEquals(
            Destination.OnChain(regtestP2wpkh, amountSats = 150_000L),
            DestinationParser.parse(uri, network),
        )
    }

    @Test
    fun `the URI scheme is not required`() {
        // iOS splits on `&:?=` rather than parsing a URI, so a payee whose QR omits
        // the scheme still gets paid. That leniency is deliberate; keep it.
        assertEquals(
            Destination.OnChain(regtestP2wpkh, amountSats = 150_000L),
            DestinationParser.parse("$regtestP2wpkh?amount=0.0015", network),
        )
    }

    // ------------------------------------------------------------------
    // Shape 3 — a BOLT-11 invoice
    // ------------------------------------------------------------------

    @Test
    fun `a BOLT-11 invoice carries the amount from its human-readable part`() {
        assertEquals(
            Destination.Lightning(invoice = invoice150Sats, amountSats = 150L),
            DestinationParser.parse(invoice150Sats, network),
        )
    }

    @Test
    fun `an invoice with no amount leaves the amount open`() {
        assertEquals(
            Destination.Lightning(invoice = invoiceNoAmount, amountSats = null),
            DestinationParser.parse(invoiceNoAmount, network),
        )
    }

    @Test
    fun `an invoice for another chain is not accepted`() {
        // `lnbcrt…` and `lnbc…` differ only in the HRP, and `bcrt` starts with `bc` —
        // the prefix test has to be exact or a regtest invoice reads as mainnet.
        assertEquals(
            Destination.Unrecognised,
            DestinationParser.parse(invoice150Sats, BitcoinNetwork.MAINNET),
        )
    }

    @Test
    fun `a unified QR prefers lightning but keeps the on-chain address`() {
        // iOS stashes the address in `bitcoinQR` (AddressParsing.swift:58-61) so Send
        // can switch rails when the invoice exceeds channel capacity. That decision
        // needs the engine, so the parser reports both and lets Send choose.
        val unified = "bitcoin:$regtestP2wpkh?amount=0.0015&lightning=$invoice150Sats"
        val parsed = DestinationParser.parse(unified, network)

        assertEquals(
            Destination.Lightning(
                invoice = invoice150Sats,
                amountSats = 150L,
                onChainFallback = Destination.OnChain(regtestP2wpkh, amountSats = 150_000L),
            ),
            parsed,
        )
    }

    // ------------------------------------------------------------------
    // Shape 4 — LNURL
    // ------------------------------------------------------------------

    @Test
    fun `a published LNURL decodes to its documented URL`() {
        // The LUD-01 example. Its plaintext is published, so this pins the whole
        // bech32 layer against something external rather than against ourselves.
        val lud01 = "LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEF" +
            "CV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XYEFHVGCXXCMYXYMNSERXFQ5FNS"

        val parsed = DestinationParser.parse(lud01, network) as Destination.Lnurl
        assertEquals(
            LnurlTarget.Service(
                "https://service.com/api?q=3fc3645b439ce8e7f2553a69e5267081d96dcd340693afabe" +
                    "04be7b0ccd178df",
            ),
            parsed.target,
        )
    }

    @Test
    fun `a lightning address becomes an lnurlp endpoint`() {
        // iOS constructs the well-known URL by hand (SendLNURL.swift:125-129).
        val parsed = DestinationParser.parse("satoshi@getbittr.com", network) as Destination.Lnurl
        assertEquals(
            LnurlTarget.Service("https://getbittr.com/.well-known/lnurlp/satoshi"),
            parsed.target,
        )
    }

    @Test
    fun `an LNURL-auth challenge is recognised as auth, not as a payment`() {
        val parsed = DestinationParser.parse(AUTH_LNURL, network) as Destination.Lnurl
        val target = parsed.target as LnurlTarget.Auth

        assertEquals(K1, target.k1Hex)
        assertEquals("login", target.action)
    }

    /**
     * **The bug BIT-84/BIT-85 recorded, and the reason BIT-100 says not to port it.**
     *
     * On iOS, LNURL *detection* lower-cases (`code.lowercased().extractLNURL()`,
     * `AddressParsing.swift:21`) while the auth *routing* compares case-sensitively —
     * `contains("tag=login&k1")` at `SendLNURL.swift:130`, and again
     * `$0.name == "tag"` / `tag == "login"` at `:150`. An LNURL whose query is
     * upper-cased is therefore detected as an LNURL and then misses the auth branch,
     * and the user is told the LNURL could not be decoded.
     *
     * Query parameter names are not required to be lower-case, so this is a
     * well-formed login request being refused.
     */
    @Test
    fun `an upper-cased auth query still routes to auth`() {
        val parsed = DestinationParser.parse(AUTH_LNURL_UPPER_QUERY, network) as Destination.Lnurl
        assertTrue(
            "An LNURL whose query reads ?TAG=LOGIN&K1=… must route to auth. Matching it " +
                "case-sensitively is the iOS bug this port exists not to repeat.",
            parsed.target is LnurlTarget.Auth,
        )
        assertEquals(K1, (parsed.target as LnurlTarget.Auth).k1Hex)
    }

    @Test
    fun `an LNURL scanned in upper case is the same LNURL`() {
        // The other half of the same bug's blast radius: bech32 QR codes are commonly
        // upper-cased, so this is the ordinary scan.
        assertEquals(
            DestinationParser.parse(AUTH_LNURL, network),
            DestinationParser.parse(AUTH_LNURL.uppercase(), network),
        )
    }

    @Test
    fun `the auth parameters need not be adjacent or in order`() {
        // `contains("tag=login&k1")` required them to be exactly adjacent, in that
        // order. Nothing in LUD-04 says they must be.
        val parsed = DestinationParser.parse(AUTH_LNURL_REORDERED, network) as Destination.Lnurl
        assertTrue(parsed.target is LnurlTarget.Auth)
    }

    @Test
    fun `a login tag with a short k1 is not treated as auth`() {
        // iOS guards on `k1Data.count == 32` (SendLNURL.swift:150) and so does this.
        // Signing a malformed challenge is worse than declining to.
        val parsed = DestinationParser.parse(AUTH_LNURL_SHORT_K1, network) as Destination.Lnurl
        assertTrue(parsed.target is LnurlTarget.Service)
    }

    @Test
    fun `a pay LNURL is a service, to be resolved by a call the parser does not make`() {
        val parsed = DestinationParser.parse(PAY_LNURL, network) as Destination.Lnurl
        assertEquals(
            LnurlTarget.Service("https://site.example/lnurl?tag=payRequest"),
            parsed.target,
        )
    }

    @Test
    fun `a bare auth URL behind a lightning scheme is recognised`() {
        // Unreachable on iOS: `extractLNURL` only looks at the pieces left after
        // splitting on `&:?=`, which shreds a URL into `https`, `//site`, `tag`,
        // `login`, … — none of which starts with `lnurl`. So the branch at
        // SendLNURL.swift:130 never fires from a scan and the user sees
        // "no bitcoin address found" for a valid login request.
        val parsed = DestinationParser.parse(
            "lightning:https://site.example/lnurl?tag=login&k1=$K1",
            network,
        ) as Destination.Lnurl
        assertTrue(parsed.target is LnurlTarget.Auth)
    }

    // ------------------------------------------------------------------
    // Precedence and the nothing-found branch
    // ------------------------------------------------------------------

    @Test
    fun `LNURL wins over an invoice, which wins over an address`() {
        // iOS's order (AddressParsing.swift:25-77). A unified QR offers the cheapest
        // rail first.
        val everything = "bitcoin:$regtestP2wpkh?lightning=$invoice150Sats&lnurl=$PAY_LNURL"
        assertTrue(DestinationParser.parse(everything, network) is Destination.Lnurl)
    }

    @Test
    fun `nothing usable is Unrecognised rather than a null`() {
        // The caller has to show "no bitcoin address found" — iOS's else branch. An
        // optional would invite a `?.let` that shows the user nothing at all.
        assertEquals(Destination.Unrecognised, DestinationParser.parse("hello world", network))
        assertEquals(Destination.Unrecognised, DestinationParser.parse("", network))
        assertEquals(Destination.Unrecognised, DestinationParser.parse("   ", network))
    }

    @Test
    fun `surrounding whitespace from a paste is ignored`() {
        assertEquals(
            Destination.OnChain(regtestP2wpkh),
            DestinationParser.parse("  $regtestP2wpkh\n", network),
        )
    }

    private companion object {
        const val K1 = "000000000000000000000000000000000000000000000000000000000000000" + "1"

        /** `https://site.example/lnurl?tag=login&k1=<K1>&action=login` */
        const val AUTH_LNURL =
            "lnurl1dp68gurn8ghj7umfw3jjuetcv9khqmr99akxuatjdslhgct884kx7emfdcnxkvfaxqcrqvp" +
                "sxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxq" +
                "crqvpsxqcrqvpsxqcrqvfxv93hg6t0dc7kcmm8d9hqn9hy4f"

        /** `https://site.example/lnurl?TAG=LOGIN&K1=<K1>` */
        const val AUTH_LNURL_UPPER_QUERY =
            "lnurl1dp68gurn8ghj7umfw3jjuetcv9khqmr99akxuatjdsl4gs2884xy736ffcnykvfaxqcrqvp" +
                "sxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxq" +
                "crqvpsxqcrqvpsxqcrqvg49hf06"

        /** `https://site.example/lnurl?k1=<K1>&tag=login` */
        const val AUTH_LNURL_REORDERED =
            "lnurl1dp68gurn8ghj7umfw3jjuetcv9khqmr99akxuatjdslkkvfaxqcrqvpsxqcrqvpsxqcrqvp" +
                "sxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxqcrqvpsxq" +
                "crqvfxw3skw0tvdankjms4v4gdh"

        /** `https://site.example/lnurl?tag=login&k1=abcd` */
        const val AUTH_LNURL_SHORT_K1 =
            "lnurl1dp68gurn8ghj7umfw3jjuetcv9khqmr99akxuatjdslhgct884kx7emfdcnxkvfav93xxeq" +
                "p97vzs"

        /** `https://site.example/lnurl?tag=payRequest` */
        const val PAY_LNURL =
            "lnurl1dp68gurn8ghj7umfw3jjuetcv9khqmr99akxuatjdslhgct884cxz72jv4ch2etnwsmcatk2"
    }
}
