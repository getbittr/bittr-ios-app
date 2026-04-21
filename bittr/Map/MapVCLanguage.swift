//
//  MapVCLanguage.swift
//  bittr
//
//  Created by Tom Melters on 4/21/26.
//

import UIKit

extension MapViewController {
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.userLocationView.backgroundColor = Colors.getColor("whiteorblue3")
        
        self.iconUserLocation.image = CacheManager.darkModeIsOn() ? UIImage(named: "iconmylocationwhite") : UIImage(named: "iconmylocationyellow")
        
        self.mapView.overrideUserInterfaceStyle = CacheManager.darkModeIsOn() ? .dark : .light
    }
}
