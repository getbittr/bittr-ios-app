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
    
    // One place
    @IBOutlet weak var onePlaceStack: UIView!
    @IBOutlet weak var onePlaceBackgroundButton: UIButton!
    @IBOutlet weak var onePlaceContainer: UIView!
    @IBOutlet weak var onePlaceContainerTop: NSLayoutConstraint!
    
    // Variables
    let locationManager = CLLocationManager()
    var hasCenteredOnUser = false
    var shouldCenterOnUserAfterAuthorization = false
    var reloadTimer: Timer?
    var currentPlaces = [BitcoinPlace]()
    var allCachedPlaces = [BitcoinPlace]()
    var visiblePlacesTask: Task<Void, Never>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Colors
        self.changeColors()
        self.setWords()
        self.setStyling()
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
        self.setPlaces()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkLocationAuthorization()
    }
    
    @IBAction func myLocationTapped(_ sender: UIButton) {
        self.goToMyLocation()
    }
    
    @IBAction func onePlaceBackgroundTapped(_ sender: UIButton) {
        self.hideOnePlace()
    }
    
    @IBAction func placeCellTapped(_ sender: UIButton) {
        self.showOnePlace(self.currentPlaces[sender.tag])
    }
    
    deinit {
        self.visiblePlacesTask?.cancel()
        self.reloadTimer?.invalidate()
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
