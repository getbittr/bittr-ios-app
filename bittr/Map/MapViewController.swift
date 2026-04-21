//
//  MapViewController.swift
//  bittr
//
//  Created by Tom Melters on 4/21/26.
//

import UIKit
import MapKit
import CoreLocation

class MapViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    
    // UI elements
    @IBOutlet weak var mapBackground: UIView!
    @IBOutlet weak var mapContainer: UIView!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var userLocationView: UIView!
    @IBOutlet weak var iconUserLocation: UIImageView!
    @IBOutlet weak var userLocationButton: UIButton!
    
    // Variables
    let locationManager = CLLocationManager()
    var hasCenteredOnUser = false
    var shouldCenterOnUserAfterAuthorization = false
    var reloadTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii
        self.mapBackground.layer.cornerRadius = 12
        self.mapBackground.setShadow()
        self.mapContainer.layer.cornerRadius = 12
        self.userLocationView.layer.cornerRadius = self.userLocationView.bounds.height/2
        self.userLocationView.setShadow()
        
        // Button titles
        self.userLocationButton.setTitle("", for: .normal)
        
        // Colors
        self.changeColors()
        self.addHeader(iconLight: "iconmapwhite", iconDark: "iconmapyellow", title: Language.getWord(withID: "paywithbitcoin"))
        
        // Map
        self.mapView.delegate = self
        self.mapView.showsUserLocation = true
        self.mapView.pointOfInterestFilter = .excludingAll
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.showDefaultSwitzerlandRegion()
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkLocationAuthorization()
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
        
        self.downloadData(lat: location.coordinate.latitude, long: location.coordinate.longitude, radius: region.span.latitudeDelta * 111 / 2)
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
            let center = mapView.centerCoordinate
            self.downloadData(lat: center.latitude, long: center.longitude, radius: mapView.region.span.latitudeDelta*111/2)
        }
    }
    
    func downloadData(lat:CGFloat, long:CGFloat, radius:CGFloat) {
        print("Will download map places.")
        Task {
            do {
                let places = try await self.fetchBTCPlaces(
                    latitude: lat,
                    longitude: long,
                    radiusKM: radius
                )

                await MainActor.run {
                    self.showPlacesOnMap(places)
                }
            } catch {
                print("Failed to fetch BTC places: \(error)")
            }
        }
    }
    
    func showPlacesOnMap(_ places: [BitcoinPlace]) {
        self.mapView.removeAnnotations(self.mapView.annotations.filter { !($0 is MKUserLocation) })
        
        for place in places {
            let annotation = MKPointAnnotation()
            annotation.coordinate = place.coordinate
            annotation.title = place.name ?? "Bitcoin place"
            
            if let address = place.address, !address.isEmpty {
                annotation.subtitle = address
            } else if let description = place.description, !description.isEmpty {
                annotation.subtitle = description
            } else if let phone = place.phone, !phone.isEmpty {
                annotation.subtitle = phone
            }
            
            self.mapView.addAnnotation(annotation)
        }
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
    
    @IBAction func myLocationTapped(_ sender: UIButton) {
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
    
}
