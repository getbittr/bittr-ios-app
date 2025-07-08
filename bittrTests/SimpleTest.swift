//
//  SimpleTest.swift
//  bittrTests
//
//  Created by Test Suite
//

import XCTest
@testable import bittr

final class SimpleTest: XCTestCase {
    
    func testBasicFunctionality() throws {
        // This is a simple test to verify our testing setup works
        XCTAssertTrue(true, "Basic test should pass")
        
        let testString = "Hello, World!"
        XCTAssertEqual(testString, "Hello, World!", "String comparison should work")
        
        let testNumber = 42
        XCTAssertGreaterThan(testNumber, 40, "Number comparison should work")
    }
    
    func testUserDefaultsAccess() throws {
        // Test that we can access UserDefaults (which CacheManager uses)
        let defaults = UserDefaults.standard
        let testKey = "test_key"
        let testValue = "test_value"
        
        // Set a value
        defaults.set(testValue, forKey: testKey)
        
        // Get the value
        let retrievedValue = defaults.string(forKey: testKey)
        
        // Verify it matches
        XCTAssertEqual(retrievedValue, testValue, "UserDefaults should work correctly")
        
        // Clean up
        defaults.removeObject(forKey: testKey)
    }
    
    func testCacheManagerImport() throws {
        // Test that we can access CacheManager
        // This will fail if there are import issues
        let testMnemonic = "test mnemonic"
        
        // Store a mnemonic
        CacheManager.storeMnemonic(mnemonic: testMnemonic)
        
        // Retrieve the mnemonic
        let retrievedMnemonic = CacheManager.getMnemonic()
        
        // Verify it matches
        XCTAssertEqual(retrievedMnemonic, testMnemonic, "CacheManager should work correctly")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "mnemonic")
    }
} 