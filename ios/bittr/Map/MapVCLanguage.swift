//
//  MapVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 4/21/26.
//

import UIKit

extension MapViewController {
    
    func setStyling() {
        
        // Corner radii
        self.mapBackground.layer.cornerRadius = 12
        self.mapBackground.setShadow()
        self.mapContainer.layer.cornerRadius = 12
        self.userLocationView.layer.cornerRadius = self.userLocationView.bounds.height/2
        self.userLocationView.setShadow()
        self.onePlaceContainer.layer.cornerRadius = 12
        
        // Button titles
        self.userLocationButton.setTitle("", for: .normal)
        self.onePlaceBackgroundButton.setTitle("", for: .normal)
        self.poweredByButton.setTitle("", for: .normal)
    }
    
    func setWords() {
        
        self.noPlacesLabel.text = Language.getWord(withID: "noplaces")
        self.topLabel.text = Language.getWord(withID: "mapvctoplabel")
        self.poweredByLabel.text = Language.getWord(withID: "mapvcpoweredby")
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.userLocationView.backgroundColor = Colors.getColor("whiteorblue3")
        self.noPlacesLabel.textColor = Colors.getColor("blackorwhite")
        self.onePlaceContainer.backgroundColor = Colors.getColor("yelloworblue1")
        self.mapSpinner.color = Colors.getColor("blackorwhite")
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        self.poweredByLabel.textColor = Colors.getColor("blackorwhite")
        
        self.iconUserLocation.image = CacheManager.darkModeIsOn() ? UIImage(named: "iconmylocationwhite") : UIImage(named: "iconmylocationyellow")
        
        self.mapView.overrideUserInterfaceStyle = CacheManager.darkModeIsOn() ? .dark : .light
    }
}
