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
    
    /// Current environment, selected by the build configuration.
    ///
    /// Debug builds (feature work / regtest) define the DEBUG compilation
    /// condition; Release builds (production) do not. This replaces the old
    /// set-environment.sh build phase + bundled environment.txt, which mutated
    /// files at build time off the git branch name (unreliable, and broke in
    /// CI's detached-HEAD checkout). Pick prod vs regtest by building
    /// Release vs Debug — no script, no branch sniffing.
    static var currentEnvironment: Environment {
        #if DEBUG
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
        isDevelopment ? "https://boltz-api.bittr.io/v2" : "https://api.boltz.exchange/v2"
    }
    
    /// Bittr API base URL based on environment
    static var bittrAPIBaseURL: String {
        isDevelopment ? "https://staging.getbittr.com/api" : "https://getbittr.com/api"
    }
    
    /// WebSocket URL based on environment
    static var webSocketURL: String {
        isDevelopment ? "wss://boltz-api.bittr.io/v2/ws" : "wss://api.boltz.exchange/v2/ws"
    }
    
    /// Electrum URL based on environment
    static var electrumURL: String {
        isDevelopment ? "tcp://electrum.bittr.io:60402" : "ssl://electrum.blockstream.info:50002"
    }
    
    /// Esplora URL based on environment
    static var esploraURL: String {
        isDevelopment ? "https://esplora-regtest.bittr.io/api" : "https://esplora.getbittr.com/api"
    }

    /// Block explorer URL based on environment
    static var explorerURL: String {
        isDevelopment ? "https://esplora-regtest.bittr.io" : "https://mempool.space"
    }
    
    /// RGS Server URL based on environment
    static var rgsServerURL: String {
        isDevelopment ? "https://rapidsync.lightningdevkit.org/testnet/snapshot/" : "https://rapidsync.lightningdevkit.org/snapshot/v2"
    }
    
    // MARK: - Lightning Configuration
    
    /// Lightning node IDs based on environment
    static var lightningNodeId: String {
        isDevelopment ? "02bbc42b52f2bf041f37e6e556c7138cdc9cc2a77175ef6c1c3d5a3fbc6fa88148" : "03e8d988a67ee7de983cd39d9d3d4d19771019305da4d2332be76c8b9fb1687776"
    }
    
    /// Lightning node addresses based on environment
    static var lightningNodeAddress: String {
        isDevelopment ? "66.163.116.210:39735" : "86.104.228.24:9735"
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

// MARK: - App Version

/// Human-readable build identity for display (e.g. the Settings screen),
/// derived from the bundle instead of being hard-coded in the storyboard.
enum AppVersion {

    /// Marketing version + build number, e.g. "0.1.179"
    /// (`CFBundleShortVersionString` + `CFBundleVersion`, which come from the
    /// `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` build settings).
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short).\(build)"
    }

    /// Short git commit the build was produced from. Written into the built
    /// Info.plist by the "Set git hash" build phase; empty when unavailable
    /// (e.g. a build made without that phase), so callers can omit it cleanly.
    static var gitHash: String {
        (Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Version with the git hash in brackets when present, e.g.
    /// "0.1.179 (a1b2c3d)" — falls back to just the version otherwise.
    static var displayString: String {
        gitHash.isEmpty ? version : "\(version) (\(gitHash))"
    }
}

// MARK: - URL Constants

extension EnvironmentConfig {
    
    /// Esplora URLs for different networks
    struct EsploraURLs {
        static let bitcoinBlockstream = "https://blockstream.info/api"
        static let bitcoinMempoolspace = "https://mempool.space/api"
        static let regtest = "https://esplora-regtest.bittr.io/api"
        static let signet = "https://mempool.space/signet/api"
        static let testnet = "https://mempool.space/testnet4/api"
    }
    
    /// RGS Server URLs for different networks
    struct RGSServerURLs {
        static let bitcoin = "https://rapidsync.lightningdevkit.org/snapshot/v2"
        static let testnet = "https://rapidsync.lightningdevkit.org/testnet/snapshot/"
    }
}
