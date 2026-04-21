//
//  BitcoinPlace.swift
//  bittr
//
//  Created by Tom Melters on 4/21/26.
//

import Foundation
import CoreLocation

struct BitcoinPlace: Decodable {
    
    let id: Int
    let lat: Double
    let lon: Double
    let icon: String?
    let name: String?
    let address: String?
    let createdAt: String?
    let updatedAt: String?
    let verifiedAt: String?
    let osmId: String?
    let phone: String?
    let website: String?
    let email: String?
    let openingHours: String?
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case lat
        case lon
        case icon
        case name
        case address
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case verifiedAt = "verified_at"
        case osmId = "osm_id"
        case phone
        case website
        case email
        case openingHours = "opening_hours"
        case description
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
}

func getBitcoinMapURL(latitude: Double, longitude: Double, radiusKM: Double) -> URL? {
    var components = URLComponents(string: "https://api.btcmap.org/v4/places/search/")
    components?.queryItems = [
        URLQueryItem(name: "lat", value: "\(latitude)"),
        URLQueryItem(name: "lon", value: "\(longitude)"),
        URLQueryItem(name: "radius_km", value: "\(radiusKM)")
    ]
    return components?.url
}

extension MapViewController {
    
    func fetchBTCPlaces(latitude: Double, longitude: Double, radiusKM: Double) async throws -> [BitcoinPlace] {
        guard let url = getBitcoinMapURL(latitude: latitude, longitude: longitude, radiusKM: radiusKM) else {
            throw NSError(domain: "BTCMap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "BTCMap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "BTCMap",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"]
            )
        }

        let decoder = JSONDecoder()
        return try decoder.decode([BitcoinPlace].self, from: data)
    }
}
