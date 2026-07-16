//
//  MapVCOnePlace.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import UIKit

extension MapViewController: UIGestureRecognizerDelegate {
    
    func showOnePlace(index:Int) {
        if let annotation = self.mapView.annotations.first(where: {
            guard let btcAnnotation = $0 as? BitcoinPlaceAnnotation else { return false }
            return btcAnnotation.index == index
        }) {
            self.isProgrammaticallyMovingMap = true
            self.isProgrammaticallyCallingOutPin = true
            self.mapView.setCenter(annotation.coordinate, animated: true)
            self.mapView.selectAnnotation(annotation, animated: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.isProgrammaticallyCallingOutPin = false
                self.updateVisiblePlacesFromCache()
            }
        }
        
        let thisPlace = self.currentPlaces[index]
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: "OnePlace")
        (newChild as? OnePlaceViewController)?.mapVC = self
        (newChild as? OnePlaceViewController)?.thisPlace = thisPlace
        
        self.addChild(newChild)
        newChild.view.frame.size = self.onePlaceContainer.frame.size
        self.onePlaceContainer.addSubview(newChild.view)
        newChild.didMove(toParent: self)
        
        self.isModalInPresentation = true
        self.onePlaceStack.alpha = 1
        self.view.layoutIfNeeded()

        // Compute the open position once (after layout) and remember it — the
        // swipe-to-dismiss handler clamps against and snaps back to it.
        let contentHeight:CGFloat = (newChild as? OnePlaceViewController)?.contentStack.bounds.height ?? 0
        self.onePlaceOpenConstant = -contentHeight - self.view.safeAreaInsets.bottom

        UIView.animate(withDuration: 0.6, delay: 0.2, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .curveEaseInOut) {

            self.onePlaceHeight.constant = contentHeight + self.view.safeAreaInsets.bottom + 20
            self.onePlaceStack.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            self.onePlaceContainerTop.constant = self.onePlaceOpenConstant
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func handleOnePlacePan(_ recognizer: UIPanGestureRecognizer) {
        // Only active while the popup is actually open.
        guard !self.onePlaceContainer.subviews.isEmpty else { return }

        let translationY = recognizer.translation(in: self.onePlaceContainer).y
        let contentHeight = -self.onePlaceOpenConstant   // open constant is negative

        switch recognizer.state {
        case .changed:
            // Only allow dragging downward (toward closed) from the open position.
            let offset = max(0, translationY)
            self.onePlaceContainerTop.constant = self.onePlaceOpenConstant + offset
            // Fade the dim out as the sheet is pulled down.
            let progress = contentHeight > 0 ? min(1, offset / contentHeight) : 0
            self.onePlaceStack.backgroundColor = .black.withAlphaComponent(0.5 * (1 - progress))
            self.view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            let velocityY = recognizer.velocity(in: self.onePlaceContainer).y
            if translationY > contentHeight / 3 || velocityY > 800 {
                self.hideOnePlace()
            } else {
                // Not far/fast enough — spring back to the open position.
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    self.onePlaceContainerTop.constant = self.onePlaceOpenConstant
                    self.onePlaceStack.backgroundColor = .black.withAlphaComponent(0.5)
                    self.view.layoutIfNeeded()
                }
            }
        default:
            break
        }
    }
    
    func hideOnePlace() {
        // Re-enable the map's sheet pull-to-dismiss now that the popup is closing.
        self.isModalInPresentation = false

        if let selectedAnnotation = self.mapView.selectedAnnotations.first {
            self.mapView.deselectAnnotation(selectedAnnotation, animated: true)
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            self.onePlaceStack.backgroundColor = UIColor.black.withAlphaComponent(0)
            self.onePlaceContainerTop.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.onePlaceStack.alpha = 0
            for eachSubview in self.onePlaceContainer.subviews {
                eachSubview.removeFromSuperview()
            }
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
