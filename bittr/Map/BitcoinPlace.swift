//
//  BitcoinPlace.swift
//  bittr
//
//  Created by Tom Melters on 4/21/26.
//

import Foundation
import CoreLocation

struct BitcoinPlace: Codable {
    
    let id: Int
    let lat: Double?
    let lon: Double?
    let icon: String?
    let name: String?
    let address: String?
    let updatedAt: String?
    let deletedAt: String?
    let website: String?
    let openingHours: String?
    
    enum CodingKeys: String, CodingKey {
        case id, lat, lon, icon, name, address, website
        case openingHours = "opening_hours"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
}

func getBitcoinMapURL(updatedSince: String?, includeDeleted: Bool) -> URL? {
    var components = URLComponents(string: "https://api.btcmap.org/v4/places")
    components?.queryItems = [
        URLQueryItem(name: "fields",
            value: "id,lat,lon,icon,name,address,website,opening_hours,updated_at,deleted_at"
        ),
        URLQueryItem(name: "include_deleted",
            value: includeDeleted ? "true" : "false"
        )
    ]
    
    if let updatedSince {
        components?.queryItems?.append(
            URLQueryItem(name: "updated_since", value: updatedSince)
        )
    }
    
    return components?.url
}

extension MapViewController {
    
    func nearbyBTCPlaces(
        from allPlaces: [BitcoinPlace],
        latitude: Double,
        longitude: Double,
        radiusKM: Double
    ) -> [BitcoinPlace] {
        
        let center = CLLocation(latitude: latitude, longitude: longitude)
        let radiusMeters = radiusKM * 1000
        
        return allPlaces.filter { place in
            guard let coordinate = place.coordinate else { return false }
            
            let placeLocation = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            
            return center.distance(from: placeLocation) <= radiusMeters
        }
    }
    
    func resyncBTCPlaces() async {
        do {
            let lastSync = UserDefaults.standard.string(forKey: "btcMapLastUpdatedAt")
            let syncedPlaces = try await syncBTCPlaces(updatedSince: lastSync)
            
            BitcoinPlacesCache.shared.applySyncedPlaces(syncedPlaces)
            
            let allCachedPlaces = BitcoinPlacesCache.shared.loadPlaces()
            
            await MainActor.run {
                self.allCachedPlaces = allCachedPlaces
                self.updateVisiblePlacesFromCache()
                Log.info("BTC places cache now contains: \(allCachedPlaces.count)")
            }
        } catch {
            Log.info("Failed to sync BTC places: \(error)")
        }
    }
    
    func syncBTCPlaces(updatedSince: String?) async throws -> [BitcoinPlace] {
        let isIncrementalSync = (updatedSince != nil)
        
        guard let url = getBitcoinMapURL(updatedSince: updatedSince, includeDeleted: isIncrementalSync) else {
            throw NSError(domain: "BTCMap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "BTCMap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "BTCMap", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
        }
        
        return try JSONDecoder().decode([BitcoinPlace].self, from: data)
    }
}


final class BitcoinPlacesCache {

    static let shared = BitcoinPlacesCache()

    private let fileName = "btc_places_cache.json"

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(fileName)
    }

    func loadPlaces() -> [BitcoinPlace] {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([BitcoinPlace].self, from: data)
        } catch {
            return []
        }
    }

    func savePlaces(_ places: [BitcoinPlace]) {
        do {
            let data = try JSONEncoder().encode(places)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save BTC places cache:", error)
        }
    }

    func applySyncedPlaces(_ syncedPlaces: [BitcoinPlace]) {
        var cachedPlaces = loadPlaces()
        
        var placesById = Dictionary(uniqueKeysWithValues: cachedPlaces.map { ($0.id, $0) })
        
        for place in syncedPlaces {
            if place.deletedAt != nil {
                placesById.removeValue(forKey: place.id)
            } else {
                placesById[place.id] = place
            }
        }
        
        cachedPlaces = Array(placesById.values)
        savePlaces(cachedPlaces)
        
        let newestUpdatedAt = syncedPlaces.compactMap { $0.updatedAt }.max()
        
        if let newestUpdatedAt {
            UserDefaults.standard.set(newestUpdatedAt, forKey: "btcMapLastUpdatedAt")
        }
    }
}
