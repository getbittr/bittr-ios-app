//
//  MapViewController.swift
//  bittr
//
//  Created by Tom Melters on 4/21/26.
//

import UIKit
import MapKit
import CoreLocation

class MapViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate, UITableViewDelegate, UITableViewDataSource {
    
    // UI elements
    @IBOutlet weak var mapBackground: UIView!
    @IBOutlet weak var mapContainer: UIView!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var userLocationView: UIView!
    @IBOutlet weak var iconUserLocation: UIImageView!
    @IBOutlet weak var userLocationButton: UIButton!
    @IBOutlet weak var placesTableView: UITableView!
    @IBOutlet weak var noPlacesLabel: UILabel!
    
    // Variables
    let locationManager = CLLocationManager()
    var hasCenteredOnUser = false
    var shouldCenterOnUserAfterAuthorization = false
    var reloadTimer: Timer?
    var currentPlaces = [BitcoinPlace]()
    var allCachedPlaces = [BitcoinPlace]()
    
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
        self.setWords()
        self.addHeader(iconLight: "iconmapwhite", iconDark: "iconmapyellow", title: Language.getWord(withID: "paywithbitcoin"))
        
        // Table view
        self.placesTableView.delegate = self
        self.placesTableView.dataSource = self
        
        // Map
        self.mapView.delegate = self
        self.mapView.showsUserLocation = true
        self.mapView.pointOfInterestFilter = .excludingAll
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.showDefaultSwitzerlandRegion()
        
        // Download
        self.allCachedPlaces = BitcoinPlacesCache.shared.loadPlaces()
        self.updateVisiblePlacesFromCache()
        
        Task {
            await self.resyncBTCPlaces()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkLocationAuthorization()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bottomSafeArea = self.view.safeAreaInsets.bottom
        self.placesTableView.contentInset = UIEdgeInsets(top: 30, left: 0, bottom: bottomSafeArea, right: 0
        )
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
        
        let nearbyPlaces = self.nearbyBTCPlaces(
            from: self.allCachedPlaces,
            latitude: center.latitude,
            longitude: center.longitude,
            radiusKM: radiusKM
        )
        
        self.showPlacesOnMap(nearbyPlaces)
    }
    
    func showPlacesOnMap(_ places: [BitcoinPlace]) {
        self.mapView.removeAnnotations(self.mapView.annotations.filter { !($0 is MKUserLocation) })
        
        for place in places {
            guard let coordinate = place.coordinate, let name = place.name else { continue }
            
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = name
            
            self.mapView.addAnnotation(annotation)
        }
        
        self.currentPlaces = places.sortByProximity(toLocation: self.mapView.centerCoordinate)
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
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.currentPlaces.count == 0 {
            self.noPlacesLabel.alpha = 1
        } else {
            self.noPlacesLabel.alpha = 0
        }
        return self.currentPlaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath) as? PlaceTableViewCell else {
            return UITableViewCell()
        }
        
        cell.layer.zPosition = CGFloat(indexPath.row)
        
        let thisPlace = self.currentPlaces[indexPath.row]
        cell.cellIcon.image = UIImage(systemName: thisPlace.icon.iconName())
        cell.placeName.text = thisPlace.name ?? "Bitcoin place"
        
        if thisPlace.address != nil {
            cell.addressStackHeight.constant = 21
            cell.addressStack.alpha = 1
            cell.placeAddress.text = thisPlace.address!
        } else {
            cell.addressStackHeight.constant = 0
            cell.addressStack.alpha = 0
            cell.placeAddress.text = ""
        }
        
        return cell
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }
        
        let identifier = "BTCPlaceMarker"
        
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if view == nil {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view?.canShowCallout = true
        } else {
            view?.annotation = annotation
        }
        
        view?.clusteringIdentifier = nil
        view?.displayPriority = .required
        
        return view
    }
    
}

extension String? {
    
    func iconName() -> String {
        
        switch self {
        case "local_cafe":
            return "cup.and.saucer.fill"
        case "restaurant", "local_dining":
            return "fork.knife"
        case "hotel":
            return "bed.double.fill"
        case "local_atm":
            return "bitcoinsign.circle.fill"
        case "shopping_cart", "store", "supermarket":
            return "cart.fill"
        case "business":
            return "building.2.fill"
        case "bar", "local_bar":
            return "wineglass.fill"
        default:
            return "mappin.circle.fill"
        }
    }
}

extension [BitcoinPlace] {
    
    func sortByProximity(toLocation:CLLocationCoordinate2D) -> [BitcoinPlace] {
        
        let centerLocation = CLLocation(
            latitude: toLocation.latitude,
            longitude: toLocation.longitude
        )
        
        return self.sorted { a, b in
            guard let coordinateA = a.coordinate else { return false }
            guard let coordinateB = b.coordinate else { return true }
            
            let locationA = CLLocation(latitude: coordinateA.latitude, longitude: coordinateA.longitude)
            let locationB = CLLocation(latitude: coordinateB.latitude, longitude: coordinateB.longitude)
            
            let distanceA = locationA.distance(from: centerLocation)
            let distanceB = locationB.distance(from: centerLocation)
            
            return distanceA < distanceB
        }
    }
}
