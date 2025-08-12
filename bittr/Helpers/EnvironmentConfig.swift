import Foundation
import LDKNode
import BitcoinDevKit

/// Environment configuration helper that reads from build settings
struct EnvironmentConfig {
    
    // MARK: - Environment Types
    
    /// Environment types for the application
    enum Environment: String, CaseIterable {
        case development = "development"
        case production = "production"
        
        /// Display name for the environment
        var displayName: String {
            switch self {
            case .development:
                return "Development"
            case .production:
                return "Production"
            }
        }
    }
    
    // MARK: - Environment Detection
    
    /// Current environment based on build settings
    static var currentEnvironment: Environment {
        // Method 1: Read from environment file created by build script
        if let bundlePath = Bundle.main.path(forResource: "environment", ofType: "txt"),
           let content = try? String(contentsOf: URL(fileURLWithPath: bundlePath)).trimmingCharacters(in: .whitespacesAndNewlines) {
            if let env = Environment(rawValue: content) {
                return env
            }
        }
        
        // Method 2: Check Info.plist (fallback)
        if let envString = Bundle.main.infoDictionary?["ENVIRONMENT"] as? String,
           let env = Environment(rawValue: envString) {
            return env
        }
        
        // Method 3: Fallback based on compilation conditions
        #if DEVELOPMENT
        return .development
        #else
        return .production
        #endif
    }
    
    // MARK: - Environment Checks
    
    /// Check if we're in development mode
    static var isDevelopment: Bool {
        currentEnvironment == .development
    }
    
    /// Check if we're in production mode
    static var isProduction: Bool {
        currentEnvironment == .production
    }
    
    // MARK: - Network Configuration
    
    /// Network selection based on environment
    static var network: BitcoinNetwork {
        isDevelopment ? .regtest : .bitcoin
    }
    
    /// LDK Network selection based on environment
    static var ldkNetwork: LDKNode.Network {
        isDevelopment ? .regtest : .bitcoin
    }
    
    /// BitcoinDevKit Network selection based on environment
    static var bitcoinDevKitNetwork: BitcoinDevKit.Network {
        isDevelopment ? .regtest : .bitcoin
    }
    
    // MARK: - API Endpoints
    
    /// Base URL for Boltz API based on environment
    static var boltzBaseURL: String {
        isDevelopment ? "https://api.regtest.getbittr.com/v2" : "https://api.boltz.exchange/v2"
    }
    
    /// Bittr API base URL based on environment
    static var bittrAPIBaseURL: String {
        isDevelopment ? "https://model-arachnid-viable.ngrok-free.app" : "https://getbittr.com/api"
    }
    
    /// WebSocket URL based on environment
    static var webSocketURL: String {
        isDevelopment ? "wss://api.regtest.getbittr.com/v2/ws" : "wss://api.boltz.exchange/v2/ws"
    }
    
    /// Electrum URL based on environment
    static var electrumURL: String {
        isDevelopment ? "tcp://regtest.getbittr.com:19001" : "ssl://electrum.blockstream.info:50002"
    }
    
    /// Esplora URL based on environment
    static var esploraURL: String {
        isDevelopment ? "https://esplora.regtest.getbittr.com/api" : "https://mempool.space/api"
    }
    
    /// RGS Server URL based on environment
    static var rgsServerURL: String {
        isDevelopment ? "https://rapidsync.lightningdevkit.org/testnet/snapshot/" : "https://rapidsync.lightningdevkit.org/snapshot/"
    }
    
    // MARK: - Lightning Configuration
    
    /// Lightning node IDs based on environment
    static var lightningNodeId: String {
        isDevelopment ? "03e46857c6c24302d7231ff42770728cc0f86296473d174f70cfca90b640dc2fd6" : "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"
    }
    
    /// Lightning node addresses based on environment
    static var lightningNodeAddress: String {
        isDevelopment ? "31.58.51.17:9735" : "86.104.228.24:9735"
    }
    
    // MARK: - Cache Configuration
    
    /// Get environment-specific cache key prefix
    static var cacheKeyPrefix: String {
        isDevelopment ? "" : "prod"
    }
    
    /// Get environment-specific cache key for a given type
    /// - Parameter type: The cache type identifier
    /// - Returns: Environment-specific cache key
    static func cacheKey(for type: String) -> String {
        cacheKeyPrefix + type
    }
    
    /// Get environment-specific cache key for device-related data
    static var deviceCacheKey: String {
        cacheKey(for: "device")
    }
}

// MARK: - URL Constants

extension EnvironmentConfig {
    
    /// Esplora URLs for different networks
    struct EsploraURLs {
        static let bitcoinBlockstream = "https://blockstream.info/api"
        static let bitcoinMempoolspace = "https://mempool.space/api"
        static let regtest = "https://esplora.regtest.getbittr.com/api"
        static let signet = "https://mutinynet.com/api"
        static let testnet = "https://mempool.space/testnet4/api"
    }
    
    /// RGS Server URLs for different networks
    struct RGSServerURLs {
        static let bitcoin = "https://rapidsync.lightningdevkit.org/snapshot/"
        static let testnet = "https://rapidsync.lightningdevkit.org/testnet/snapshot/"
    }
}
