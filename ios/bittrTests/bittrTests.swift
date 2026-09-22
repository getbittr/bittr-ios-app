//
//  bittrTests.swift
//  bittrTests
//
//  Created by Tom Melters on 23/03/2023.
//

import XCTest
import CryptoKit
import BitcoinDevKit
@testable import bittr

final class bittrTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

// MARK: - Number parsing and money conversion
//
// Covers the money-critical helpers introduced by the parsing refactor: the
// exact-Decimal conversion to satoshis, the machine- vs user-format parsers,
// the fee-rate helpers, and the (display-only) CGFloat conversion. Expected
// Decimals are built against a fixed locale so the assertions don't depend on
// the test runner's region.

final class NumberAndMoneyTests: XCTestCase {

    /// A Decimal parsed against a fixed locale, matching `parsedNumber()`.
    private func dec(_ string: String) -> Decimal {
        return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    // MARK: parsedNumber() — machine format (API responses, cached values)

    func testParsedNumberBasic() {
        XCTAssertEqual("123.45".parsedNumber(), dec("123.45"))
        XCTAssertEqual("0".parsedNumber(), Decimal(0))
        XCTAssertEqual("1000000".parsedNumber(), Decimal(1_000_000))
        XCTAssertEqual("0.00000001".parsedNumber(), dec("0.00000001"))
    }

    func testParsedNumberAcceptsCommaDecimal() {
        // A machine value may use a comma as the decimal point.
        XCTAssertEqual("123,45".parsedNumber(), dec("123.45"))
    }

    func testParsedNumberSign() {
        XCTAssertEqual("-5".parsedNumber(), Decimal(-5))
        XCTAssertEqual("+5".parsedNumber(), Decimal(5))
    }

    func testParsedNumberRejectsInvalid() {
        XCTAssertNil("".parsedNumber())
        XCTAssertNil("   ".parsedNumber())
        XCTAssertNil("abc".parsedNumber())
        XCTAssertNil(".".parsedNumber())          // no digit
        XCTAssertNil("1.2.3".parsedNumber())       // more than one separator
        XCTAssertNil("1,234.56".parsedNumber())    // grouping is not machine format
    }

    // MARK: Decimal -> satoshis (the exact send path)

    func testSatoshisFromBitcoinIsExact() {
        XCTAssertEqual(dec("0.00000001").satoshisFromBitcoin(), 1)
        XCTAssertEqual(Decimal(1).satoshisFromBitcoin(), 100_000_000)
        XCTAssertEqual(dec("0.5").satoshisFromBitcoin(), 50_000_000)
        XCTAssertEqual(dec("0.1").satoshisFromBitcoin(), 10_000_000)
        XCTAssertEqual(dec("20999999.99999999").satoshisFromBitcoin(), 2_099_999_999_999_999)
    }

    func testSatoshisRoundingAndBounds() {
        // 1.5 satoshis rounds to the nearest whole satoshi.
        XCTAssertEqual(dec("0.000000015").satoshisFromBitcoin(), 2)
        // The full 21 M supply is the accepted maximum.
        XCTAssertEqual(Decimal(21_000_000).satoshisFromBitcoin(), Bitcoin.maximumSatoshis)
        // Anything above the supply is rejected rather than clamped.
        XCTAssertNil(Decimal(21_000_001).satoshisFromBitcoin())
        // Negatives are rejected.
        XCTAssertNil(Decimal(-1).satoshis())
    }

    // MARK: parsedUserAmount() — what a person types

    func testUserAmountWholeSatoshis() {
        // A whole-satoshi field has no decimal point.
        XCTAssertEqual("1234".parsedUserAmount(allowingFraction: false)?.satoshis(), 1234)
        // Grouping separators (incl. the Swiss apostrophe and spaces) are stripped.
        XCTAssertEqual("1 234 567".parsedUserAmount(allowingFraction: false)?.satoshis(), 1_234_567)
        XCTAssertEqual("1'234'567".parsedUserAmount(allowingFraction: false)?.satoshis(), 1_234_567)
    }

    func testUserAmountBitcoinToSatoshis() {
        XCTAssertEqual("0.5".parsedUserAmount()?.satoshisFromBitcoin(), 50_000_000)
        XCTAssertEqual("1".parsedUserAmount()?.satoshisFromBitcoin(), 100_000_000)
        XCTAssertEqual("0.00000001".parsedUserAmount()?.satoshisFromBitcoin(), 1)
    }

    func testUserAmountBothSeparatorConventions() {
        // US style: comma groups, dot is the decimal point.
        XCTAssertEqual("1,234.56".parsedUserAmount(), dec("1234.56"))
        // European style: dot groups, comma is the decimal point.
        XCTAssertEqual("1.234,56".parsedUserAmount(), dec("1234.56"))
    }

    func testUserAmountRepeatedSeparatorIsGrouping() {
        // The same separator repeated can only be grouping.
        XCTAssertEqual("1.234.567".parsedUserAmount(), Decimal(1_234_567))
        XCTAssertEqual("1,234,567".parsedUserAmount(), Decimal(1_234_567))
    }

    func testUserAmountNonThreeDigitFractionIsDecimal() {
        // A fraction length other than 3 makes the separator unambiguously decimal.
        XCTAssertEqual("1.5".parsedUserAmount(), dec("1.5"))
        XCTAssertEqual("1.50".parsedUserAmount(), dec("1.50"))
        XCTAssertEqual("0.12345678".parsedUserAmount(), dec("0.12345678"))
    }

    func testUserAmountRejectsMalformed() {
        XCTAssertNil("1.2.3".parsedUserAmount())          // groups of one aren't thousands
        XCTAssertNil("1234.567.890".parsedUserAmount())   // leading group of four isn't valid grouping
        XCTAssertNil("abc".parsedUserAmount())
    }

    func testUserAmountThreeDigitAmbiguityFollowsLocale() {
        // "1.234" with a 3-digit fraction is the genuinely ambiguous case and
        // resolves per the device locale's decimal separator.
        let result = "1.234".parsedUserAmount()
        if Locale.current.decimalSeparator == "." {
            XCTAssertEqual(result, dec("1.234"))   // dot is decimal -> 1.234
        } else {
            XCTAssertEqual(result, Decimal(1234))  // dot is grouping -> 1234
        }
    }

    // MARK: Fee-rate helpers

    func testWholeSatPerVb() {
        XCTAssertEqual(Double(2.9).wholeSatPerVb, 2)   // floored to what is broadcast
        XCTAssertEqual(Double(10.0).wholeSatPerVb, 10)
        XCTAssertEqual(Double(1.0).wholeSatPerVb, 1)   // minimum one
        XCTAssertEqual(Double(0.5).wholeSatPerVb, 1)   // below one clamps to one
    }

    func testFeeSats() {
        XCTAssertEqual(Double(5.0).feeSats(forVsize: 200.0), 1000)
        XCTAssertEqual(Double(2.9).feeSats(forVsize: 100.0), 200) // 2 sat/vB * 100 vB
        XCTAssertEqual(Double(5.0).feeSats(forVsize: 0), 0)
    }

    // MARK: CGFloat display conversion

    func testCGFloatInSatoshis() {
        XCTAssertEqual(CGFloat(0.1).inSatoshis(), 10_000_000)
        XCTAssertEqual(CGFloat(1).inSatoshis(), 100_000_000)
        XCTAssertEqual(CGFloat(0).inSatoshis(), 0)
        XCTAssertEqual(CGFloat(-1).inSatoshis(), 0)     // non-positive -> 0
        XCTAssertEqual(CGFloat(22_000_000).inSatoshis(), Bitcoin.maximumSatoshis) // clamped to supply
    }
}

// MARK: - RIPEMD-160

final class RIPEMD160Tests: XCTestCase {

    // The canonical RIPEMD-160 test vectors. If any constant table in the
    // implementation is transcribed wrong, one of these breaks.
    func testStandardVectors() {
        let cases: [(String, String)] = [
            ("", "9c1185a5c5e9fc54612808977ee8f548b2258d31"),
            ("a", "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe"),
            ("abc", "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"),
            ("message digest", "5d0689ef49d2fae572b881b123a85ffa21595f36"),
            ("abcdefghijklmnopqrstuvwxyz", "f71c27109c692c1b56bbdceb5b9d2865b3708dbc"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
             "12a053384a9c0c88e405a06c27dcf49ada62eb2b")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(RIPEMD160.hash(Data(input.utf8)).hex, expected, "RIPEMD160(\"\(input)\")")
        }
    }

    // A million 'a's: exercises many blocks and the padding path.
    func testLongVector() {
        let input = Data(Array(repeating: UInt8(ascii: "a"), count: 1_000_000))
        XCTAssertEqual(RIPEMD160.hash(input).hex, "52783243c1697bdbe16d37f97f68f08325dc1528")
    }

    // HASH160 = RIPEMD160(SHA256(x)).
    func testHash160Composition() {
        let data = Data("abc".utf8)
        let expected = RIPEMD160.hash(Data(SHA256.hash(data: data))).hex
        XCTAssertEqual(RIPEMD160.hash160(data).hex, expected)
    }
}

// MARK: - Reverse-swap claim-leaf preimage-hash check

final class BoltzClaimLeafTests: XCTestCase {

    // Real claimLeaf from a regtest reverse swap (the comment block in
    // SwapManager.lightningToOnchain), and the HASH160(preimage) it commits to.
    private let regtestClaimLeaf = "82012088a91475b687397f92783b38c7381725bfcf27d65eef3f8820036f6171920eec6d2f377e4c0ab88960307c7d9d817ddf65585bc28a8334be1aac"
    private let regtestLeafHash160 = "75b687397f92783b38c7381725bfcf27d65eef3f"

    func testParsesHash160FromRealLeaf() throws {
        let hash = try BoltzSwapValidation.claimLeafPreimageHash160(regtestClaimLeaf)
        XCTAssertEqual(hash.hex, regtestLeafHash160)
    }

    // A layout that isn't exactly OP_SIZE 32 EQUALVERIFY HASH160 <20> ... must
    // throw rather than silently return the wrong 20 bytes.
    func testRejectsMalformedLeaf() {
        XCTAssertThrowsError(try BoltzSwapValidation.claimLeafPreimageHash160("82012088a914"))                         // truncated
        XCTAssertThrowsError(try BoltzSwapValidation.claimLeafPreimageHash160("00" + String(regtestClaimLeaf.dropFirst(2)))) // wrong first opcode
        XCTAssertThrowsError(try BoltzSwapValidation.claimLeafPreimageHash160(regtestClaimLeaf + "ff"))                // trailing byte
        XCTAssertThrowsError(try BoltzSwapValidation.claimLeafPreimageHash160("zz"))                                   // not hex
    }

    // Round-trip: build a leaf around HASH160(ourPreimage), confirm the parser
    // recovers exactly that, and that a different hash does not match.
    func testHash160RoundTripThroughLeaf() throws {
        let preimage = Data((0..<32).map { UInt8($0) })
        let expected = RIPEMD160.hash160(preimage)
        let dummyKey = String(repeating: "ab", count: 32)   // 32-byte x-only key placeholder
        let genuineLeaf = "82012088a914" + expected.hex + "8820" + dummyKey + "ac"
        XCTAssertEqual(try BoltzSwapValidation.claimLeafPreimageHash160(genuineLeaf), expected)

        let tamperedLeaf = "82012088a914" + String(repeating: "00", count: 20) + "8820" + dummyKey + "ac"
        XCTAssertNotEqual(try BoltzSwapValidation.claimLeafPreimageHash160(tamperedLeaf), expected)
    }
}

// MARK: - Reverse-swap lockup validation (end-to-end)

// Exercises the whole validateReverseLockup path — address check, our-key check,
// and the claim-leaf preimage-hash check — instead of only the parser. This is
// the trustlessness case we can't yet drive through the live EvilBoltz flow: a
// rogue Boltz funds a lockup whose address and our claim key both check out, but
// whose claim leaf commits to a preimage we do NOT hold, so the uncooperative
// script-path claim would be unspendable by us. The check must reject it before
// the invoice is paid.
//
// We can't capture a real swap's private key, so we stand in a known keypair
// (privkey 0x01, whose public key is the secp256k1 generator point G) and derive
// the lockup address exactly the way the app does (tweakedLockupKey), reusing a
// real regtest Boltz refund key + refund leaf. Both the address and our-key
// checks then pass on genuine data, so a wrong preimage can only be caught by
// the claim-leaf hash check under test.
final class BoltzReverseLockupTests: XCTestCase {

    // privkey 0x01 → public key G; Gx is its x-only key and G has an even Y, so
    // the compressed key is 02 || Gx.
    private let ourPrivateKeyHex = String(repeating: "0", count: 63) + "1"
    private let ourXonlyKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    private var ourClaimPublicKeyHex: String { "02" + ourXonlyKey }

    // A real regtest Boltz refund key + refund leaf (from the lightningToOnchain
    // example response), used only as Boltz's side of the aggregate.
    private let boltzRefundPublicKey = "035578a38b772461f2481b2a9c6f6802419b11282fb3719cde6af337c077e3d5f3"
    private let refundLeaf = "205578a38b772461f2481b2a9c6f6802419b11282fb3719cde6af337c077e3d5f3ad024d01b1"

    private let ourPreimage = Data((0..<32).map { UInt8($0) })

    private func claimLeaf(committingTo preimage: Data) -> String {
        "82012088a914" + RIPEMD160.hash160(preimage).hex + "8820" + ourXonlyKey + "ac"
    }

    // The P2TR lockup address our keys + these leaves actually produce. Gated
    // against the production decoder so an encoder bug can't masquerade as a
    // validateReverseLockup pass/fail.
    private func lockupAddress(claimLeafHex: String) throws -> String {
        let tweaked = try BoltzSwapValidation.tweakedLockupKey(
            boltzPublicKeyHex: boltzRefundPublicKey,
            ourPrivateKeyHex: ourPrivateKeyHex,
            claimLeafOutputHex: claimLeafHex,
            refundLeafOutputHex: refundLeaf
        )
        let address = Bech32mEncoder.encodeP2TR(program: tweaked, hrp: "bcrt")
        var expectedScript = Data([0x51, 0x20])
        expectedScript.append(tweaked)
        XCTAssertEqual(AddressHandler.toOutputScript(address: address, network: .regtest), expectedScript,
                       "test bech32m encoder must round-trip through the production decoder")
        return address
    }

    // Genuine reverse lockup: the claim leaf commits to the preimage we hold, so
    // the whole validation passes.
    func testAcceptsSelfConsistentReverseLockup() throws {
        let leaf = claimLeaf(committingTo: ourPreimage)
        let address = try lockupAddress(claimLeafHex: leaf)
        XCTAssertNoThrow(try BoltzSwapValidation.validateReverseLockup(
            address: address,
            refundPublicKeyHex: boltzRefundPublicKey,
            claimPrivateKeyHex: ourPrivateKeyHex,
            ourClaimPublicKeyHex: ourClaimPublicKeyHex,
            preimageHex: ourPreimage.hex,
            claimLeafOutputHex: leaf,
            refundLeafOutputHex: refundLeaf,
            network: .regtest
        ))
    }

    // The adversarial case: the leaf commits to a preimage only Boltz holds, and
    // the address is the one that leaf really produces (so the address and
    // our-key checks pass). Only the claim-leaf hash check stands between us and
    // paying for coins we could never claim on the script path.
    func testRejectsClaimLeafCommittingToAnotherPreimage() throws {
        let boltzOnlyPreimage = Data((0..<32).map { UInt8(0xff - $0) })
        let tamperedLeaf = claimLeaf(committingTo: boltzOnlyPreimage)
        let address = try lockupAddress(claimLeafHex: tamperedLeaf)

        XCTAssertThrowsError(try BoltzSwapValidation.validateReverseLockup(
            address: address,
            refundPublicKeyHex: boltzRefundPublicKey,
            claimPrivateKeyHex: ourPrivateKeyHex,
            ourClaimPublicKeyHex: ourClaimPublicKeyHex,
            preimageHex: ourPreimage.hex,                 // we hold THIS preimage, not the leaf's
            claimLeafOutputHex: tamperedLeaf,
            refundLeafOutputHex: refundLeaf,
            network: .regtest
        )) { error in
            guard case SwapValidationError.claimLeafHashMismatch = error else {
                return XCTFail("expected claimLeafHashMismatch, got \(error)")
            }
        }
    }
}

// Minimal BIP-350 bech32m encoder — TEST ONLY. bittr ships only a decoder
// (Bech32.decode / AddressHandler.toOutputScript); building a lockup address
// from an output key needs the encode direction, which is why the end-to-end
// reverse-lockup case was blocked before. Every address it produces is gated
// against the production decoder in BoltzReverseLockupTests.lockupAddress(...).
private enum Bech32mEncoder {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i in 0..<5 { chk ^= ((top >> i) & 1) == 0 ? 0 : generator[i] }
        }
        return chk
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let b = Array(hrp.utf8)
        return b.map { $0 >> 5 } + [0] + b.map { $0 & 31 }
    }

    private static func to5Bit(_ data: [UInt8]) -> [UInt8] {
        var acc = 0, bits = 0, ret: [UInt8] = []
        for value in data {
            acc = (acc << 8) | Int(value)
            bits += 8
            while bits >= 5 { bits -= 5; ret.append(UInt8((acc >> bits) & 31)) }
        }
        if bits > 0 { ret.append(UInt8((acc << (5 - bits)) & 31)) }
        return ret
    }

    // Witness version 1 + 32-byte program, checksummed with the bech32m constant.
    static func encodeP2TR(program: Data, hrp: String) -> String {
        let data = [UInt8(1)] + to5Bit(Array(program))
        let mod = polymod(hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]) ^ 0x2bc830a3
        let checksum = (0..<6).map { UInt8((mod >> (5 * (5 - $0))) & 31) }
        return hrp + "1" + String((data + checksum).map { charset[Int($0)] })
    }
}

// MARK: - BDK wallet persistence: does Wallet.load validate its descriptors?

// Settles the one unknown blocking a change to didStartBDK. Today the wallet
// database is wiped on every launch (Connection.createConnection) and rebuilt
// with the create initializer, so every launch pays for a full scan. Loading
// the existing database instead is only safe if Wallet.load refuses a database
// that belongs to a different seed — otherwise a load could succeed against the
// previous wallet's history and report someone else's balance.
//
// The Swift bindings can't answer that: load(descriptor:changeDescriptor:
// connection:) takes the descriptors but no network, and whether it applies
// them as checks isn't visible from the generated interface. So ask the library.
//
// testLoadRejectsADatabaseFromAnotherSeed is the load-bearing one. If it fails,
// loading persisted wallets is off the table and the unconditional wipe stays.
//
// Every database here is a throwaway file in the test bundle's temporary
// directory. Nothing touches the app's Documents directory or a real wallet.

final class BDKWalletLoadTests: XCTestCase {

    // Public BIP39 test vectors, chosen so neither is anyone's wallet. Only
    // their descriptors are derived here; nothing is broadcast or spent.
    private let seedA = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private let seedB = "legal winner thank year wave sausage worth useful legal winner thank yellow"

    // Pinned rather than taken from EnvironmentConfig, so the result doesn't
    // depend on which configuration the tests were built with.
    private let network = Network.testnet

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bdk-load-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func databasePath() -> String {
        return directory.appendingPathComponent("wallet.sqlite").path
    }

    // The same derivation didStartBDK performs.
    private func descriptors(for words: String) throws -> (external: Descriptor, change: Descriptor) {
        let mnemonic = try Mnemonic.fromString(mnemonic: words)
        let rootKey = DescriptorSecretKey(network: network, mnemonic: mnemonic, password: nil)
        return (Descriptor.newBip84(secretKey: rootKey, keychain: .external, network: network),
                Descriptor.newBip84(secretKey: rootKey, keychain: .internal, network: network))
    }

    // Creates a wallet at `path`, reveals a few addresses so the changeset has
    // something in it, and persists.
    @discardableResult
    private func createAndPersist(seed words: String, at path: String, revealingTo index: UInt32 = 5) throws -> String {
        let keys = try descriptors(for: words)
        let connection = try Connection(path: path)
        let wallet = try Wallet(descriptor: keys.external,
                                changeDescriptor: keys.change,
                                network: network,
                                connection: connection)
        _ = wallet.revealAddressesTo(keychain: .external, index: index)
        _ = try wallet.persist(connection: connection)
        return wallet.peekAddress(keychain: .external, index: 0).address.description
    }

    // MARK: The question this file exists to answer

    // A database written by seed A must not load under seed B's descriptors.
    func testLoadRejectsADatabaseFromAnotherSeed() throws {

        let path = databasePath()
        try createAndPersist(seed: seedA, at: path)

        let otherKeys = try descriptors(for: seedB)
        let connection = try Connection(path: path)

        XCTAssertThrowsError(
            try Wallet.load(descriptor: otherKeys.external,
                            changeDescriptor: otherKeys.change,
                            connection: connection),
            "Wallet.load accepted a database belonging to a different seed. Loading a "
            + "persisted wallet would then be able to report the wrong balance, so "
            + "didStartBDK must keep wiping and recreating."
        ) { error in
            XCTAssertTrue(error is LoadWithPersistError,
                          "expected a LoadWithPersistError, got \(error)")
        }
    }

    // MARK: The paths the production change would rely on

    // The matching seed loads, and brings its persisted state back with it.
    func testLoadReturnsThePersistedWalletForTheSameSeed() throws {

        let path = databasePath()
        let addressBefore = try createAndPersist(seed: seedA, at: path, revealingTo: 5)

        let keys = try descriptors(for: seedA)
        let connection = try Connection(path: path)
        let loaded = try Wallet.load(descriptor: keys.external,
                                     changeDescriptor: keys.change,
                                     connection: connection)

        XCTAssertEqual(loaded.peekAddress(keychain: .external, index: 0).address.description,
                       addressBefore)

        // Revealing again to the index already persisted must produce nothing
        // new — which it only can if the revealed index survived. That index is
        // what makes a light sync sufficient for a loaded wallet.
        XCTAssertEqual(loaded.revealAddressesTo(keychain: .external, index: 5).count, 0,
                       "the persisted revealed-address index did not come back")
    }

    // An empty database must fail rather than hand back a blank wallet, so the
    // create fallback is reachable and distinguishable.
    func testLoadFailsOnAnEmptyDatabase() throws {

        let keys = try descriptors(for: seedA)
        let connection = try Connection(path: databasePath())

        XCTAssertThrowsError(
            try Wallet.load(descriptor: keys.external,
                            changeDescriptor: keys.change,
                            connection: connection)
        ) { error in
            guard case LoadWithPersistError.CouldNotLoad = error else {
                // Not a failure of the production design, but worth knowing:
                // the fallback would need to catch this case too.
                return XCTFail("expected .CouldNotLoad for an empty database, got \(error)")
            }
        }
    }

    // A freshly created wallet reveals addresses that a reloaded one already
    // has. Guards the assertion above against passing for the wrong reason.
    func testFreshWalletRevealsAddressesThatAReloadedOneDoesNot() throws {

        let path = databasePath()
        let keys = try descriptors(for: seedA)
        let connection = try Connection(path: path)
        let wallet = try Wallet(descriptor: keys.external,
                                changeDescriptor: keys.change,
                                network: network,
                                connection: connection)

        XCTAssertGreaterThan(wallet.revealAddressesTo(keychain: .external, index: 5).count, 0)
    }
}
