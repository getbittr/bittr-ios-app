//
//  CacheManagerTests.swift
//  bittr
//
//  Created by Ruben Waterman on 08/07/2025.
//

import XCTest
@testable import bittr

final class CacheManagerTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Clear UserDefaults before each test to ensure clean state
        clearUserDefaults()
    }
    
    override func tearDownWithError() throws {
        // Clear UserDefaults after each test to clean up
        clearUserDefaults()
    }
    
    // MARK: - Helper Methods
    
    private func clearUserDefaults() {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        dictionary.keys.forEach { key in
            defaults.removeObject(forKey: key)
        }
    }
    
    private func setEnvironment(_ isProduction: Bool) {
        UserDefaults.standard.set(isProduction ? 1 : 0, forKey: "envkey")
    }
    
    // MARK: - Environment Tests
    
    func testEnvironmentKeyManagement() throws {
        // Test development environment
        setEnvironment(false)
        XCTAssertEqual(UserDefaults.standard.value(forKey: "envkey") as? Int, 0)
        
        // Test production environment
        setEnvironment(true)
        XCTAssertEqual(UserDefaults.standard.value(forKey: "envkey") as? Int, 1)
    }
    
    // MARK: - Client Info Management Tests
    
    func testDeleteClientInfoDevelopment() throws {
        setEnvironment(false)
        
        // Setup test data
        let testDeviceData: [String: Any] = ["test": "data"]
        UserDefaults.standard.set(testDeviceData, forKey: "device")
        UserDefaults.standard.set("test", forKey: "cache")
        UserDefaults.standard.set("1234", forKey: "pin")
        UserDefaults.standard.set("test mnemonic", forKey: "mnemonic")
        UserDefaults.standard.set("test address", forKey: "lastaddress")
        UserDefaults.standard.set("test lightning", forKey: "lightning")
        
        // Verify data exists
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "device"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "cache"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "pin"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "mnemonic"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "lastaddress"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "lightning"))
        
        // Delete client info
        CacheManager.deleteClientInfo()
        
        // Verify data is deleted
        XCTAssertNil(UserDefaults.standard.value(forKey: "device"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "cache"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "pin"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "mnemonic"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "lastaddress"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "lightning"))
    }
    
    func testDeleteClientInfoProduction() throws {
        setEnvironment(true)
        
        // Setup test data
        let testDeviceData: [String: Any] = ["test": "data"]
        UserDefaults.standard.set(testDeviceData, forKey: "proddevice")
        UserDefaults.standard.set("test", forKey: "prodcache")
        UserDefaults.standard.set("1234", forKey: "prodpin")
        UserDefaults.standard.set("test mnemonic", forKey: "prodmnemonic")
        UserDefaults.standard.set("test address", forKey: "prodlastaddress")
        UserDefaults.standard.set("test lightning", forKey: "prodlightning")
        
        // Verify data exists
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "proddevice"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "prodcache"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "prodpin"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "prodmnemonic"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "prodlastaddress"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "prodlightning"))
        
        // Delete client info
        CacheManager.deleteClientInfo()
        
        // Verify data is deleted
        XCTAssertNil(UserDefaults.standard.value(forKey: "proddevice"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "prodcache"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "prodpin"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "prodmnemonic"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "prodlastaddress"))
        XCTAssertNil(UserDefaults.standard.value(forKey: "prodlightning"))
    }
    
    // MARK: - Cache Management Tests
    
    func testDeleteCache() throws {
        setEnvironment(false)
        
        // Setup test data
        UserDefaults.standard.set("test cache", forKey: "cache")
        UserDefaults.standard.set("other data", forKey: "other")
        
        // Verify cache exists
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "cache"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
        
        // Delete cache
        CacheManager.deleteCache()
        
        // Verify cache is deleted but other data remains
        XCTAssertNil(UserDefaults.standard.value(forKey: "cache"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
    }
    
    func testDeleteCacheProduction() throws {
        setEnvironment(true)
        
        // Setup test data
        UserDefaults.standard.set("test cache", forKey: "prodcache")
        UserDefaults.standard.set("other data", forKey: "other")
        
        // Verify cache exists
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "prodcache"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
        
        // Delete cache
        CacheManager.deleteCache()
        
        // Verify cache is deleted but other data remains
        XCTAssertNil(UserDefaults.standard.value(forKey: "prodcache"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
    }
    
    // MARK: - Lightning Transaction Tests
    
    func testDeleteLightningTransactions() throws {
        setEnvironment(false)
        
        // Setup test data
        UserDefaults.standard.set("test lightning", forKey: "lightning")
        UserDefaults.standard.set("other data", forKey: "other")
        
        // Verify lightning data exists
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "lightning"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
        
        // Delete lightning transactions
        CacheManager.deleteLightningTransactions()
        
        // Verify lightning data is deleted but other data remains
        XCTAssertNil(UserDefaults.standard.value(forKey: "lightning"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
    }
    
    func testDeleteLightningTransactionsProduction() throws {
        setEnvironment(true)
        
        // Setup test data
        UserDefaults.standard.set("test lightning", forKey: "prodlightning")
        UserDefaults.standard.set("other data", forKey: "other")
        
        // Verify lightning data exists
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "prodlightning"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
        
        // Delete lightning transactions
        CacheManager.deleteLightningTransactions()
        
        // Verify lightning data is deleted but other data remains
        XCTAssertNil(UserDefaults.standard.value(forKey: "prodlightning"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
    }
    
    // MARK: - Image Cache Tests
    
    func testEmptyImage() throws {
        // Setup test data
        UserDefaults.standard.set(["test": "image"], forKey: "articleimages")
        UserDefaults.standard.set("other data", forKey: "other")
        
        // Verify image data exists
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "articleimages"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
        
        // Empty image cache
        CacheManager.emptyImage()
        
        // Verify image data is deleted but other data remains
        XCTAssertNil(UserDefaults.standard.value(forKey: "articleimages"))
        XCTAssertNotNil(UserDefaults.standard.value(forKey: "other"))
    }
    
    func testStoreAndGetImage() throws {
        let testKey = "test_image_key"
        let testData = "test image data".data(using: .utf8)!
        
        // Store image
        CacheManager.storeImageInCache(key: testKey, data: testData)
        
        // Get image
        let retrievedData = CacheManager.getImage(key: testKey)
        
        // Verify data matches
        XCTAssertEqual(retrievedData, testData)
    }
    
    func testGetImageNotFound() throws {
        let testKey = "nonexistent_key"
        
        // Try to get non-existent image
        let retrievedData = CacheManager.getImage(key: testKey)
        
        // Verify nil is returned
        XCTAssertNil(retrievedData)
    }
    
    // MARK: - Mnemonic Tests
    
    func testStoreAndGetMnemonicDevelopment() throws {
        setEnvironment(false)
        let testMnemonic = "test mnemonic phrase"
        
        // Store mnemonic
        CacheManager.storeMnemonic(mnemonic: testMnemonic)
        
        // Get mnemonic
        let retrievedMnemonic = CacheManager.getMnemonic()
        
        // Verify mnemonic matches
        XCTAssertEqual(retrievedMnemonic, testMnemonic)
    }
    
    func testStoreAndGetMnemonicProduction() throws {
        setEnvironment(true)
        let testMnemonic = "test mnemonic phrase"
        
        // Store mnemonic
        CacheManager.storeMnemonic(mnemonic: testMnemonic)
        
        // Get mnemonic
        let retrievedMnemonic = CacheManager.getMnemonic()
        
        // Verify mnemonic matches
        XCTAssertEqual(retrievedMnemonic, testMnemonic)
    }
    
    func testGetMnemonicNotFound() throws {
        setEnvironment(false)
        
        // Try to get non-existent mnemonic
        let retrievedMnemonic = CacheManager.getMnemonic()
        
        // Verify nil is returned
        XCTAssertNil(retrievedMnemonic)
    }
    
    // MARK: - PIN Tests
    
    func testStoreAndGetPinDevelopment() throws {
        setEnvironment(false)
        let testPin = "1234"
        
        // Store PIN
        CacheManager.storePin(pin: testPin)
        
        // Get PIN
        let retrievedPin = CacheManager.getPin()
        
        // Verify PIN matches
        XCTAssertEqual(retrievedPin, testPin)
    }
    
    func testStoreAndGetPinProduction() throws {
        setEnvironment(true)
        let testPin = "1234"
        
        // Store PIN
        CacheManager.storePin(pin: testPin)
        
        // Get PIN
        let retrievedPin = CacheManager.getPin()
        
        // Verify PIN matches
        XCTAssertEqual(retrievedPin, testPin)
    }
    
    func testGetPinNotFound() throws {
        setEnvironment(false)
        
        // Try to get non-existent PIN
        let retrievedPin = CacheManager.getPin()
        
        // Verify nil is returned
        XCTAssertNil(retrievedPin)
    }
    
    // MARK: - Notification Token Tests
    
    func testStoreAndGetNotificationsToken() throws {
        let testToken = "test_notification_token"
        
        // Store token
        CacheManager.storeNotificationsToken(token: testToken)
        
        // Get token
        let retrievedToken = CacheManager.getRegistrationToken()
        
        // Verify token matches
        XCTAssertEqual(retrievedToken, testToken)
    }
    
    func testGetNotificationsTokenNotFound() throws {
        // Try to get non-existent token
        let retrievedToken = CacheManager.getRegistrationToken()
        
        // Verify nil is returned
        XCTAssertNil(retrievedToken)
    }
    
    // MARK: - PIN Security Tests
    
    func testFailedPinAttempts() throws {
        setEnvironment(false)
        
        // Initially should be 0
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 0)
        
        // Increase failed attempts
        CacheManager.increaseFailedPinAttempts()
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 1)
        
        CacheManager.increaseFailedPinAttempts()
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 2)
        
        // Reset failed attempts
        CacheManager.resetFailedPinAttempts()
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 0)
    }
    
    func testFailedPinAttemptsProduction() throws {
        setEnvironment(true)
        
        // Initially should be 0
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 0)
        
        // Increase failed attempts
        CacheManager.increaseFailedPinAttempts()
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 1)
        
        CacheManager.increaseFailedPinAttempts()
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 2)
        
        // Reset failed attempts
        CacheManager.resetFailedPinAttempts()
        XCTAssertEqual(CacheManager.getFailedPinAttempts(), 0)
    }
    
    // MARK: - Address Tests
    
    func testStoreAndGetLastAddressDevelopment() throws {
        setEnvironment(false)
        let testAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Store address
        CacheManager.storeLastAddress(newAddress: testAddress)
        
        // Get address
        let retrievedAddress = CacheManager.getLastAddress()
        
        // Verify address matches
        XCTAssertEqual(retrievedAddress, testAddress)
    }
    
    func testStoreAndGetLastAddressProduction() throws {
        setEnvironment(true)
        let testAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // Store address
        CacheManager.storeLastAddress(newAddress: testAddress)
        
        // Get address
        let retrievedAddress = CacheManager.getLastAddress()
        
        // Verify address matches
        XCTAssertEqual(retrievedAddress, testAddress)
    }
    
    func testGetLastAddressNotFound() throws {
        setEnvironment(false)
        
        // Try to get non-existent address
        let retrievedAddress = CacheManager.getLastAddress()
        
        // Verify nil is returned
        XCTAssertNil(retrievedAddress)
    }
    
    // MARK: - TxoID Tests
    
    func testStoreAndGetTxoIDDevelopment() throws {
        setEnvironment(false)
        let testTxoID = "test_txo_id"
        
        // Store TxoID
        CacheManager.storeTxoID(txoID: testTxoID)
        
        // Get TxoID
        let retrievedTxoID = CacheManager.getTxoID()
        
        // Verify TxoID matches
        XCTAssertEqual(retrievedTxoID, testTxoID)
    }
    
    func testStoreAndGetTxoIDProduction() throws {
        setEnvironment(true)
        let testTxoID = "test_txo_id"
        
        // Store TxoID
        CacheManager.storeTxoID(txoID: testTxoID)
        
        // Get TxoID
        let retrievedTxoID = CacheManager.getTxoID()
        
        // Verify TxoID matches
        XCTAssertEqual(retrievedTxoID, testTxoID)
    }
    
    func testGetTxoIDNotFound() throws {
        setEnvironment(false)
        
        // Try to get non-existent TxoID
        let retrievedTxoID = CacheManager.getTxoID()
        
        // Verify nil is returned
        XCTAssertNil(retrievedTxoID)
    }
    
    // MARK: - Sent to Bittr Tests
    
    func testUpdateAndGetSentToBittrDevelopment() throws {
        setEnvironment(false)
        let testTxIDs = ["tx1", "tx2", "tx3"]
        
        // Update sent to Bittr
        CacheManager.updateSentToBittr(txids: testTxIDs)
        
        // Get sent to Bittr
        let retrievedTxIDs = CacheManager.getSentToBittr()
        
        // Verify TxIDs match
        XCTAssertEqual(retrievedTxIDs, testTxIDs)
    }
    
    func testUpdateAndGetSentToBittrProduction() throws {
        setEnvironment(true)
        let testTxIDs = ["tx1", "tx2", "tx3"]
        
        // Update sent to Bittr
        CacheManager.updateSentToBittr(txids: testTxIDs)
        
        // Get sent to Bittr
        let retrievedTxIDs = CacheManager.getSentToBittr()
        
        // Verify TxIDs match
        XCTAssertEqual(retrievedTxIDs, testTxIDs)
    }
    
    func testUpdateSentToBittrAppends() throws {
        setEnvironment(false)
        let initialTxIDs = ["tx1", "tx2"]
        let additionalTxIDs = ["tx3", "tx4"]
        
        // Add initial TxIDs
        CacheManager.updateSentToBittr(txids: initialTxIDs)
        
        // Add additional TxIDs
        CacheManager.updateSentToBittr(txids: additionalTxIDs)
        
        // Get all TxIDs
        let retrievedTxIDs = CacheManager.getSentToBittr()
        
        // Verify all TxIDs are present
        XCTAssertEqual(retrievedTxIDs?.count, 4)
        XCTAssertTrue(retrievedTxIDs?.contains("tx1") ?? false)
        XCTAssertTrue(retrievedTxIDs?.contains("tx2") ?? false)
        XCTAssertTrue(retrievedTxIDs?.contains("tx3") ?? false)
        XCTAssertTrue(retrievedTxIDs?.contains("tx4") ?? false)
    }
    
    func testGetSentToBittrNotFound() throws {
        setEnvironment(false)
        
        // Try to get non-existent sent to Bittr
        let retrievedTxIDs = CacheManager.getSentToBittr()
        
        // Verify nil is returned
        XCTAssertNil(retrievedTxIDs)
    }
    
    // MARK: - Event Handling Tests
    
    func testDidHandleEvent() throws {
        let testEvent = "test_event"
        
        // Mark event as handled
        CacheManager.didHandleEvent(event: testEvent)
        
        // Check if event was handled
        XCTAssertTrue(CacheManager.hasHandledEvent(event: testEvent))
    }
    
    func testHasHandledEventNotFound() throws {
        let testEvent = "nonexistent_event"
        
        // Check if non-existent event was handled
        XCTAssertFalse(CacheManager.hasHandledEvent(event: testEvent))
    }
    
    func testMultipleEvents() throws {
        let event1 = "event1"
        let event2 = "event2"
        
        // Mark events as handled
        CacheManager.didHandleEvent(event: event1)
        CacheManager.didHandleEvent(event: event2)
        
        // Check if both events were handled
        XCTAssertTrue(CacheManager.hasHandledEvent(event: event1))
        XCTAssertTrue(CacheManager.hasHandledEvent(event: event2))
    }
    
    // MARK: - Notification Tests
    
    func testStoreAndGetLatestNotification() throws {
        let testNotification: [String: Any] = ["key": "value", "number": 123]
        
        // Store notification
        CacheManager.storeLatestNotification(specialData: testNotification)
        
        // Get notification
        let retrievedNotification = CacheManager.getLatestNotification()
        
        // Verify notification matches
        XCTAssertEqual(retrievedNotification?["key"] as? String, "value")
        XCTAssertEqual(retrievedNotification?["number"] as? Int, 123)
    }
    
    func testGetLatestNotificationNotFound() throws {
        // Try to get non-existent notification
        let retrievedNotification = CacheManager.getLatestNotification()
        
        // Verify nil is returned
        XCTAssertNil(retrievedNotification)
    }
    
    // MARK: - Dark Mode Tests
    
    func testDarkMode() throws {
        // Initially should be false
        XCTAssertFalse(CacheManager.darkModeIsOn())
        
        // Enable dark mode
        CacheManager.updateDarkMode(isOn: true)
        XCTAssertTrue(CacheManager.darkModeIsOn())
        
        // Disable dark mode
        CacheManager.updateDarkMode(isOn: false)
        XCTAssertFalse(CacheManager.darkModeIsOn())
    }
    
    // MARK: - Language Tests
    
    func testLanguage() throws {
        // Initially should be "en_US"
        XCTAssertEqual(CacheManager.getLanguage(), "en_US")
        
        // Change language
        CacheManager.changeLanguage("de_DE")
        XCTAssertEqual(CacheManager.getLanguage(), "de_DE")
        
        // Change back
        CacheManager.changeLanguage("en_US")
        XCTAssertEqual(CacheManager.getLanguage(), "en_US")
    }
    
    // MARK: - Swap Tests
    
    func testSaveAndGetLatestSwap() throws {
        let testSwap: [String: Any] = ["swapId": "123", "status": "pending"]
        let swapDict = NSDictionary(dictionary: testSwap)
        
        // Save swap
        CacheManager.saveLatestSwap(swapDict)
        
        // Get swap
        let retrievedSwap = CacheManager.getLatestSwap()
        
        // Verify swap matches
        XCTAssertEqual(retrievedSwap?["swapId"] as? String, "123")
        XCTAssertEqual(retrievedSwap?["status"] as? String, "pending")
    }
    
    func testSaveLatestSwapNil() throws {
        // Save some swap first
        let testSwap: [String: Any] = ["swapId": "123"]
        CacheManager.saveLatestSwap(NSDictionary(dictionary: testSwap))
        
        // Verify swap exists
        XCTAssertNotNil(CacheManager.getLatestSwap())
        
        // Save nil to clear
        CacheManager.saveLatestSwap(nil)
        
        // Verify swap is cleared
        XCTAssertNil(CacheManager.getLatestSwap())
    }
    
    func testGetLatestSwapNotFound() throws {
        // Try to get non-existent swap
        let retrievedSwap = CacheManager.getLatestSwap()
        
        // Verify nil is returned
        XCTAssertNil(retrievedSwap)
    }
} 
