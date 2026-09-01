//
//  MapVCTable.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import UIKit

extension MapViewController {
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bottomSafeArea = self.view.safeAreaInsets.bottom
        self.placesTableView.contentInset = UIEdgeInsets(top: 60, left: 0, bottom: bottomSafeArea, right: 0
        )
        self.poweredByFade.addGradient()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.currentPlaces.count == 0, !self.mapSpinner.isAnimating {
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
        cell.placeName.accessibilityIdentifier = TestID.Map.placeName
        cell.cellButton.tag = indexPath.row
        cell.cellButton.accessibilityIdentifier = TestID.Map.placeCellButton
        
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
}
