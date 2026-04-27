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
    @IBOutlet weak var mapSpinner: UIActivityIndicatorView!
    
    // One place
    @IBOutlet weak var onePlaceStack: UIView!
    @IBOutlet weak var onePlaceBackgroundButton: UIButton!
    @IBOutlet weak var onePlaceContainer: UIView!
    @IBOutlet weak var onePlaceContainerTop: NSLayoutConstraint!
    @IBOutlet weak var onePlaceHeight: NSLayoutConstraint!
    
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
