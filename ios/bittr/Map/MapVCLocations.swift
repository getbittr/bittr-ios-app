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
        self.mapSpinner.startAnimating()
        self.noPlacesLabel.alpha = 0
        
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
        if self.isProgrammaticallyMovingMap {
            self.isProgrammaticallyMovingMap = false
            return
        }

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
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self?.showPlacesOnMap(nearbyPlaces)
            }
        }
    }
    
    func showPlacesOnMap(_ places: [BitcoinPlace]) {
        // Cap to the nearest N places to the map centre. A zoomed-out region
        // (e.g. the ~422 km Switzerland fallback) can match thousands of
        // places; adding an annotation for each one plus the table reload
        // hangs the app. The region-change debounce re-runs this as the user
        // pans/zooms, so the visible set stays the N nearest to the centre.
        let maxVisiblePlaces = 200
        self.currentPlaces = Array(places.sortByProximity(toLocation: self.mapView.centerCoordinate).prefix(maxVisiblePlaces))

        let existingAnnotations = self.mapView.annotations.compactMap {
            $0 as? BitcoinPlaceAnnotation
        }
        
        for annotation in existingAnnotations {
            let stillExists = self.currentPlaces.contains { $0.id == annotation.placeID }
            
            if !stillExists {
                self.mapView.removeAnnotation(annotation)
            }
        }
        
        for (index, place) in self.currentPlaces.enumerated() {
            guard let coordinate = place.coordinate, let name = place.name else { continue }
            
            if let existingAnnotation = existingAnnotations.first(where: { $0.placeID == place.id }) {
                
                existingAnnotation.index = index
            } else {
                let annotation = BitcoinPlaceAnnotation()
                annotation.coordinate = coordinate
                annotation.title = name
                annotation.index = index
                annotation.placeID = place.id
                
                self.mapView.addAnnotation(annotation)
            }
        }
        
        self.placesTableView.reloadData()
        self.placesTableView.layoutIfNeeded()
        DispatchQueue.main.async { self.placesTableView.setContentOffset(CGPoint(x: 0, y: -30), animated: true) }
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
        Log.info("Location error: \(error)")
        self.showDefaultSwitzerlandRegion()
    }
    
    func goToMyLocation() {
        DispatchQueue.global(qos: .background).async {
            guard CLLocationManager.locationServicesEnabled() else {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "locationunavailable"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
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
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "locationunavailable"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
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
        
        view?.markerTintColor = UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: 1)
        view?.glyphText = "₿"
        view?.glyphTintColor = .black
        //view?.clusteringIdentifier = nil
        //view?.displayPriority = .required
        
        return view
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if self.isProgrammaticallyCallingOutPin {
            self.isProgrammaticallyCallingOutPin = false
            return
        }
        guard let annotation = view.annotation as? BitcoinPlaceAnnotation else { return }
        mapView.deselectAnnotation(annotation, animated: false)
        
        self.showOnePlace(index: annotation.index)
    }
}

class BitcoinPlaceAnnotation: MKPointAnnotation {
    var index: Int = 0
    var placeID: Int = 0
}
