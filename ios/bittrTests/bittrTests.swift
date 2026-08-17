//
//  bittrTests.swift
//  bittrTests
//
//  Created by Tom Melters on 23/03/2023.
//

import XCTest
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
