# Bittr iOS App - Test Plan

## Overview
This document outlines a comprehensive testing strategy for the Bittr iOS app, a Bitcoin/Lightning wallet application with features including wallet management, transactions, swaps, IBAN integration, and more.

## Current State
- ✅ Test targets exist (`bittrTests` and `bittrUITests`)
- ❌ Only template tests are present (no actual test implementation)
- ❌ No test coverage for critical functionality

## Test Categories

### 1. Unit Tests (bittrTests)

#### 1.1 Core Services & Managers
- [x] **CacheManager Tests** ✅ COMPLETED
  - [x] `deleteClientInfo()` - Test environment-specific deletion
  - [x] `deleteCache()` - Test cache clearing
  - [x] `deleteLightningTransactions()` - Test lightning transaction deletion
  - [x] `parseDevice()` - Test device data parsing
  - [x] `addIban()` - Test IBAN addition to clients
  - [x] `addEmailToken()` - Test email token management
  - [x] `storeMnemonic()` / `getMnemonic()` - Test mnemonic storage/retrieval
  - [x] `storePin()` / `getPin()` - Test PIN storage/retrieval
  - [x] `storeNotificationsToken()` / `getNotificationsToken()` - Test notification token management
  - [x] `resetFailedPinAttempts()` / `incrementFailedPinAttempts()` - Test PIN security
  - [x] `storeCache()` / `getCache()` - Test general cache operations

- [ ] **BittrService Tests**
  - [ ] `payoutLightning()` - Test Lightning payout functionality
  - [ ] `fetchBittrTransactions()` - Test transaction fetching
  - [ ] Error handling for network failures
  - [ ] Error handling for server errors
  - [ ] Response parsing and validation

- [ ] **LightningNodeService Tests**
  - [ ] `start()` - Test Lightning node initialization
  - [ ] `startBDK()` - Test Bitcoin Dev Kit initialization
  - [ ] `nodeId()` - Test node ID retrieval
  - [ ] `signMessage()` - Test message signing
  - [ ] `stop()` - Test node shutdown
  - [ ] Channel management operations
  - [ ] Balance calculations
  - [ ] Network switching (testnet/regtest/bitcoin)

#### 1.2 Helper Classes
- [ ] **Reachability Tests**
  - [ ] Network connectivity detection
  - [ ] Connection type detection

- [ ] **Transaction Tests**
  - [ ] Transaction creation and validation
  - [ ] Transaction parsing

- [ ] **Model Tests**
  - [ ] `Client` model validation
  - [ ] `IbanEntity` model validation
  - [ ] `Channel` model validation
  - [ ] `Article` model validation

#### 1.3 Utilities
- [ ] **Colors Tests**
  - [ ] Color retrieval for different themes
  - [ ] Dark/light mode color switching

- [ ] **Language Tests**
  - [ ] Word retrieval functionality
  - [ ] Language switching

- [ ] **ChainXS Tests** (Bitcoin utilities)
  - [ ] Address validation
  - [ ] Bech32 encoding/decoding
  - [ ] HD wallet operations

### 2. Integration Tests

#### 2.1 Wallet Operations
- [ ] **Wallet Creation Flow**
  - [ ] New wallet generation
  - [ ] Mnemonic creation and storage
  - [ ] PIN setup

- [ ] **Wallet Restoration Flow**
  - [ ] Mnemonic import
  - [ ] Wallet recovery
  - [ ] Data synchronization

- [ ] **Lightning Network Integration**
  - [ ] Channel opening
  - [ ] Payment sending/receiving
  - [ ] Channel management

#### 2.2 Transaction Management
- [ ] **On-chain Transactions**
  - [ ] Transaction creation
  - [ ] Fee calculation
  - [ ] Transaction broadcasting

- [ ] **Lightning Transactions**
  - [ ] Invoice creation
  - [ ] Payment processing
  - [ ] Channel balance updates

#### 2.3 Swap Operations
- [ ] **SwapManager Tests**
  - [ ] Swap initiation
  - [ ] Swap execution
  - [ ] Swap status tracking
  - [ ] Error handling

- [ ] **WebSocketManager Tests**
  - [ ] Connection management
  - [ ] Message handling
  - [ ] Reconnection logic

### 3. UI Tests (bittrUITests)

#### 3.1 Core User Flows
- [ ] **App Launch Flow**
  - [ ] Initial app launch
  - [ ] App launch with existing wallet
  - [ ] App launch without wallet

- [ ] **Wallet Setup Flow**
  - [ ] New wallet creation
  - [ ] PIN setup
  - [ ] Wallet restoration

- [ ] **Authentication Flow**
  - [ ] PIN entry
  - [ ] Failed PIN attempts
  - [ ] PIN reset

#### 3.2 Main App Features
- [ ] **Home Screen**
  - [ ] Balance display
  - [ ] Transaction list
  - [ ] Currency switching
  - [ ] Navigation buttons

- [ ] **Send Money**
  - [ ] Lightning payment flow
  - [ ] On-chain payment flow
  - [ ] QR code scanning
  - [ ] Address validation

- [ ] **Receive Money**
  - [ ] Invoice generation
  - [ ] QR code display
  - [ ] Address sharing

- [ ] **Buy Bitcoin**
  - [ ] IBAN registration
  - [ ] Purchase flow
  - [ ] Payment processing

- [ ] **Swaps**
  - [ ] Swap initiation
  - [ ] Swap execution
  - [ ] Swap status tracking

#### 3.3 Settings & Configuration
- [ ] **Settings Screen**
  - [ ] Language switching
  - [ ] Currency preferences
  - [ ] Security settings

- [ ] **Device Management**
  - [ ] Device registration
  - [ ] Device removal

### 4. Performance Tests

#### 4.1 App Performance
- [ ] **App Launch Time**
  - [ ] Cold start performance
  - [ ] Warm start performance

- [ ] **Memory Usage**
  - [ ] Memory consumption monitoring
  - [ ] Memory leak detection

- [ ] **Battery Usage**
  - [ ] Background processing impact
  - [ ] Network usage optimization

#### 4.2 Network Performance
- [ ] **API Response Times**
  - [ ] Transaction fetching
  - [ ] Price updates
  - [ ] Swap operations

- [ ] **Lightning Network Performance**
  - [ ] Channel operations
  - [ ] Payment routing

### 5. Security Tests

#### 5.1 Data Protection
- [ ] **Sensitive Data Storage**
  - [ ] Mnemonic encryption
  - [ ] PIN security
  - [ ] Private key protection

- [ ] **Network Security**
  - [ ] API communication security
  - [ ] WebSocket security
  - [ ] Certificate validation

#### 5.2 Authentication & Authorization
- [ ] **PIN Security**
  - [ ] PIN validation
  - [ ] Failed attempt handling
  - [ ] PIN reset functionality

- [ ] **Session Management**
  - [ ] App backgrounding
  - [ ] Session timeout
  - [ ] Re-authentication

### 6. Accessibility Tests

#### 6.1 VoiceOver Support
- [ ] **Screen Reader Compatibility**
  - [ ] All UI elements properly labeled
  - [ ] Navigation flow accessible

#### 6.2 Dynamic Type
- [ ] **Text Scaling**
  - [ ] UI adapts to text size changes
  - [ ] No text truncation

### 7. Localization Tests

#### 7.1 Language Support
- [ ] **Multi-language Support**
  - [ ] All text properly localized
  - [ ] RTL language support (if applicable)

#### 7.2 Regional Settings
- [ ] **Currency Formatting**
  - [ ] Different currency displays
  - [ ] Number formatting

### 8. Widget Tests

#### 8.1 BittrWidget
- [ ] **Widget Functionality**
  - [ ] Widget display
  - [ ] Deep linking
  - [ ] Data updates

### 9. Error Handling Tests

#### 9.1 Network Errors
- [ ] **Offline Mode**
  - [ ] App behavior without network
  - [ ] Cached data usage

- [ ] **API Failures**
  - [ ] Server error handling
  - [ ] Timeout handling
  - [ ] Retry mechanisms

#### 9.2 User Error Scenarios
- [ ] **Invalid Input**
  - [ ] Invalid addresses
  - [ ] Invalid amounts
  - [ ] Invalid PINs

### 10. Edge Cases

#### 10.1 Boundary Conditions
- [ ] **Amount Limits**
  - [ ] Minimum transaction amounts
  - [ ] Maximum transaction amounts
  - [ ] Balance edge cases

- [ ] **Network Conditions**
  - [ ] Slow network handling
  - [ ] Intermittent connectivity

## Test Implementation Priority

### Phase 1: Critical Core Functionality
1. CacheManager tests
2. Basic wallet operations
3. PIN authentication
4. Core UI flows

### Phase 2: Financial Operations
1. Transaction management
2. Lightning operations
3. Swap functionality
4. Buy/sell flows

### Phase 3: Advanced Features
1. Performance tests
2. Security tests
3. Accessibility tests
4. Edge cases

### Phase 4: Polish & Optimization
1. Localization tests
2. Widget tests
3. Error handling improvements
4. Performance optimization

## Test Environment Setup

### Required Test Data
- [ ] Test Bitcoin addresses
- [ ] Test Lightning invoices
- [ ] Mock API responses
- [ ] Test IBAN data
- [ ] Sample transaction data

### Test Configuration
- [ ] Testnet/regtest network setup
- [ ] Mock server configuration
- [ ] Test device configurations
- [ ] CI/CD pipeline setup

## Success Metrics

### Code Coverage Targets
- Unit Tests: 80%+ coverage
- Integration Tests: 70%+ coverage
- UI Tests: 60%+ coverage

### Performance Targets
- App launch: < 3 seconds
- Transaction processing: < 5 seconds
- UI responsiveness: < 100ms

### Quality Gates
- All critical tests passing
- No high-priority bugs
- Performance benchmarks met
- Security scan passed

## Notes
- Tests should use testnet/regtest networks to avoid real Bitcoin transactions
- Mock external services where appropriate
- Use dependency injection for better testability
- Implement proper test data management
- Consider using snapshot testing for UI components

## Progress Tracking
- [x] Phase 1.1 Complete (CacheManager Tests)
- [ ] Phase 1.2 Complete (BittrService Tests)
- [ ] Phase 1.3 Complete (LightningNodeService Tests)
- [ ] Phase 2 Complete  
- [ ] Phase 3 Complete
- [ ] Phase 4 Complete
- [ ] All Tests Passing
- [ ] Documentation Complete 