//
//  OnePlaceViewController.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import UIKit
import MapKit

class OnePlaceViewController: UIViewController {
    
    // UI elements
    @IBOutlet weak var contentStack: UIView!
    @IBOutlet weak var placeNameLabel: UILabel!
    @IBOutlet weak var iconImage: UIImageView!
    @IBOutlet weak var typeLabel: UILabel!
    @IBOutlet weak var closeButton: UIButton!
    
    // Address
    @IBOutlet weak var addressStack: UIView!
    @IBOutlet weak var addressStackHeight: NSLayoutConstraint!
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var addressLabel: UILabel!
    
    // Website
    @IBOutlet weak var websiteStack: UIView!
    @IBOutlet weak var websiteStackHeight: NSLayoutConstraint!
    @IBOutlet weak var websiteView: UIView!
    @IBOutlet weak var websiteLabel: UILabel!
    @IBOutlet weak var websiteButton: UIButton!
    
    // Opening hours
    @IBOutlet weak var hoursStack: UIView!
    @IBOutlet weak var hoursStackHeight: NSLayoutConstraint!
    @IBOutlet weak var hoursView: UIView!
    @IBOutlet weak var hoursLabel: UILabel!
    
    // Go to Maps
    @IBOutlet weak var goToMapsView: UIView!
    @IBOutlet weak var goToMapsLabel: UILabel!
    @IBOutlet weak var goToMapsButton: UIButton!
    
    // Variables
    var mapVC:MapViewController?
    var thisPlace:BitcoinPlace?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Styling
        self.changeColors()
        self.setStyling()

        // Maestro test IDs.
        self.placeNameLabel.accessibilityIdentifier = TestID.Map.OnePlace.nameLabel
        self.closeButton.accessibilityIdentifier = TestID.Map.OnePlace.closeButton
        self.websiteButton.accessibilityIdentifier = TestID.Map.OnePlace.websiteButton
        self.goToMapsButton.accessibilityIdentifier = TestID.Map.OnePlace.goToMapsButton

        // Populate page.
        self.placeNameLabel.text = self.thisPlace!.name ?? Language.getWord(withID: "unavailable")
        self.iconImage.image = UIImage(systemName: self.thisPlace!.icon.iconName())
        self.typeLabel.text = self.thisPlace!.icon.categoryDescription()
        if self.thisPlace!.address != nil {
            self.showAddress()
        }
        if self.thisPlace!.website != nil {
            self.showWebsite()
        }
        if self.thisPlace!.openingHours != nil {
            self.showHours()
        }
    }
    
    func showAddress() {
        self.addressLabel.text = self.thisPlace!.address!
        self.addressStack.alpha = 1
        NSLayoutConstraint.deactivate([self.addressStackHeight])
        self.addressStackHeight = NSLayoutConstraint(item: self.addressStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.addressStackHeight])
        self.view.layoutIfNeeded()
    }
    
    func showWebsite() {
        var website = self.thisPlace!.website!.replacingOccurrences(of: "www.", with: "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
        if website.last == "/" {
            website.removeLast()
        }
        self.websiteLabel.text = website
        self.websiteStack.alpha = 1
        NSLayoutConstraint.deactivate([self.websiteStackHeight])
        self.websiteStackHeight = NSLayoutConstraint(item: self.websiteStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.websiteStackHeight])
        self.view.layoutIfNeeded()
    }
    
    func showHours() {
        self.hoursLabel.text = self.thisPlace!.openingHours!
        self.hoursStack.alpha = 1
        NSLayoutConstraint.deactivate([self.hoursStackHeight])
        self.hoursStackHeight = NSLayoutConstraint(item: self.hoursStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.hoursStackHeight])
        self.view.layoutIfNeeded()
    }
    
    @IBAction func closeTapped(_ sender: UIButton) {
        self.mapVC?.hideOnePlace()
    }
    
    func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.placeNameLabel.textColor = Colors.getColor("blackoryellow")
        self.addressView.backgroundColor = Colors.getColor("whiteorblue3")
        self.websiteView.backgroundColor = Colors.getColor("whiteorblue3")
        self.hoursView.backgroundColor = Colors.getColor("whiteorblue3")
        self.addressLabel.textColor = Colors.getColor("blackorwhite")
        self.websiteLabel.textColor = Colors.getColor("blackorwhite")
        self.hoursLabel.textColor = Colors.getColor("blackorwhite")
        self.goToMapsView.backgroundColor = Colors.getColor("white0.7orblue3")
    }
    
    func setStyling() {
        
        // Buttons
        self.closeButton.setTitle("", for: .normal)
        self.websiteButton.setTitle("", for: .normal)
        self.goToMapsButton.setTitle("", for: .normal)
        
        // Corner radii
        self.addressView.layer.cornerRadius = 8
        self.websiteView.layer.cornerRadius = 8
        self.hoursView.layer.cornerRadius = 8
        self.goToMapsView.layer.cornerRadius = 8
        self.goToMapsView.setShadow()
        
        // Words
        self.goToMapsLabel.text = Language.getWord(withID: "openinmaps")
    }
    
    @IBAction func websiteTapped(_ sender: UIButton) {
        self.performSegue(withIdentifier: "OnePlaceToWebsite", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "OnePlaceToWebsite" {
            if let websiteVC = segue.destination as? WebsiteViewController {
                websiteVC.tappedUrl = self.thisPlace!.website!
            }
        }
    }
    
    @IBAction func goToMapsTapped(_ sender: UIButton) {
        
        if UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            self.showAlert(presentingController: self.mapVC ?? self, title: Language.getWord(withID: "openinmaps"), message: Language.getWord(withID: "openinmaps2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "openinmaps4"), Language.getWord(withID: "openinmaps3")], actions: [nil, #selector(self.openInAppleMaps), #selector(self.openInGoogleMaps)])
        } else {
            self.openInAppleMaps()
        }
    }
    
    @objc func openInAppleMaps() {
        let coordinate = CLLocationCoordinate2D(latitude: self.thisPlace!.lat!, longitude: self.thisPlace!.lon!)
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = self.thisPlace!.name!
        mapItem.openInMaps(launchOptions: nil)
    }
    
    @objc func openInGoogleMaps() {
        let urlString = "comgooglemaps://?q=\(self.thisPlace!.lat!),\(self.thisPlace!.lon!)"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
}
