//
//  OnePlaceViewController.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import UIKit

class OnePlaceViewController: UIViewController {
    
    // Variables
    var mapVC:MapViewController?
    var thisPlace:BitcoinPlace?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.changeColors()
    }
    
    func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
    
}
