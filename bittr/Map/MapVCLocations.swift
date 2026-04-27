//
//  MapVCLocations.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import UIKit
import MapKit
import CoreLocation

extension MapViewController {
    
    func setPlaces() {
        
        Task.detached(priority: .utility) { [weak self] in
            let cachedPlaces = BitcoinPlacesCache.shared.loadPlaces()
            await MainActor.run {
                self?.allCachedPlaces = cachedPlaces
                self?.updateVisiblePlacesFromCache()
            }
        }
        
        Task {
            await self.resyncBTCPlaces()
        }
    }
    
    func checkLocationAuthorization() {
        switch self.locationManager.authorizationStatus {
        case .notDetermined:
            self.locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            self.showDefaultSwitzerlandRegion()
        case .authorizedWhenInUse, .authorizedAlways:
            self.locationManager.requestLocation()
        @unknown default:
            self.showDefaultSwitzerlandRegion()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if self.shouldCenterOnUserAfterAuthorization {
            self.shouldCenterOnUserAfterAuthorization = false
            manager.requestLocation()
        } else {
            self.checkLocationAuthorization()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 1500,
            longitudinalMeters: 1500
        )
        
        if !self.hasCenteredOnUser {
            self.hasCenteredOnUser = true
            self.mapView.setRegion(region, animated: true)
        }
        
        self.updateVisiblePlacesFromCache()
    }
    
    func centerMap(on coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1500,
            longitudinalMeters: 1500
        )
        self.mapView.setRegion(region, animated: true)
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        self.reloadTimer?.invalidate()
        self.reloadTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            self.updateVisiblePlacesFromCache()
        }
    }
    
    func updateVisiblePlacesFromCache() {
        let center = self.mapView.centerCoordinate
        let radiusKM = self.mapView.region.span.latitudeDelta * 111
        let allPlaces = self.allCachedPlaces
        
        self.visiblePlacesTask?.cancel()
        
        self.visiblePlacesTask = Task.detached(priority: .userInitiated) { [weak self] in
            let nearbyPlaces = allPlaces.nearbyBTCPlaces(
                latitude: center.latitude,
                longitude: center.longitude,
                radiusKM: radiusKM
            )
            
            let sortedPlaces = nearbyPlaces.sortByProximity(toLocation: center)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self?.showPlacesOnMap(nearbyPlaces)
            }
        }
    }
    
    func showPlacesOnMap(_ places: [BitcoinPlace]) {
        self.mapView.removeAnnotations(self.mapView.annotations.filter { !($0 is MKUserLocation) })
        
        self.currentPlaces = places.sortByProximity(toLocation: self.mapView.centerCoordinate)
        
        for (index, place) in self.currentPlaces.enumerated() {
            guard let coordinate = place.coordinate, let name = place.name else { continue }
            
            let annotation = BitcoinPlaceAnnotation()
            annotation.coordinate = coordinate
            annotation.title = name
            annotation.index = index
            
            self.mapView.addAnnotation(annotation)
        }
        
        self.placesTableView.reloadData()
    }
    
    func showDefaultSwitzerlandRegion() {
        let switzerlandCenter = CLLocationCoordinate2D(latitude: 46.8182, longitude: 8.2275)
        let region = MKCoordinateRegion(
            center: switzerlandCenter,
            span: MKCoordinateSpan(latitudeDelta: 3.8, longitudeDelta: 5.0)
        )
        self.mapView.setRegion(region, animated: false)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
        self.showDefaultSwitzerlandRegion()
    }
    
    func goToMyLocation() {
        DispatchQueue.global(qos: .background).async {
            guard CLLocationManager.locationServicesEnabled() else {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "locationunavailable"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            
            DispatchQueue.main.async {
                self.hasCenteredOnUser = false
                
                switch self.locationManager.authorizationStatus {
                case .notDetermined:
                    self.shouldCenterOnUserAfterAuthorization = true
                    self.locationManager.requestWhenInUseAuthorization()
                case .authorizedWhenInUse, .authorizedAlways:
                    if let cachedLocation = self.locationManager.location{
                        self.centerMap(on: cachedLocation.coordinate)
                    }
                    self.locationManager.requestLocation()
                case .restricted, .denied:
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "locationunavailable"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                @unknown default:
                    break
                }
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }
        
        let identifier = "BTCPlaceMarker"
        
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if view == nil {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view?.canShowCallout = false
        } else {
            view?.annotation = annotation
        }
        
        view?.clusteringIdentifier = nil
        view?.displayPriority = .required
        
        return view
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation as? BitcoinPlaceAnnotation else { return }
        mapView.deselectAnnotation(annotation, animated: false)
        
        self.showOnePlace(self.currentPlaces[annotation.index])
    }
}

class BitcoinPlaceAnnotation: MKPointAnnotation {
    var index: Int = 0
}
