//
//  OnePlaceViewController.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import UIKit

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
    
    // Variables
    var mapVC:MapViewController?
    var thisPlace:BitcoinPlace?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Styling
        self.changeColors()
        self.setStyling()
        
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
    }
    
    func setStyling() {
        
        // Buttons
        self.closeButton.setTitle("", for: .normal)
        self.websiteButton.setTitle("", for: .normal)
        
        // Corner radii
        self.addressView.layer.cornerRadius = 8
        self.websiteView.layer.cornerRadius = 8
        self.hoursView.layer.cornerRadius = 8
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
    
}
