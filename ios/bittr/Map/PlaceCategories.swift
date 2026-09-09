//
//  PlaceCategories.swift
//  bittr
//
//  Created by Tom Melters on 4/27/26.
//

import Foundation

extension String? {
    
    func iconName() -> String {
        
        switch self {
            
        // Food & Drink
        case "local_cafe":
            return "cup.and.saucer.fill"
        case "restaurant", "local_dining", "lunch_dining":
            return "fork.knife"
        case "local_pizza":
            return "fork.knife.circle.fill"
        case "local_bar", "bar", "sports_bar":
            return "wineglass.fill"
        case "cake":
            return "birthday.cake.fill"
        case "icecream":
            return "birthday.cake"
            
        // Stay / Accommodation
        case "hotel":
            return "bed.double.fill"
        case "cottage":
            return "house.fill"
            
        // Bitcoin / Finance
        case "local_atm":
            return "bitcoinsign.circle.fill"
        case "account_balance":
            return "building.columns.fill"
            
        // Shopping / Retail
        case "shopping_cart", "store", "supermarket":
            return "cart.fill"
        case "storefront":
            return "storefront.fill"
        case "local_grocery_store":
            return "basket.fill"
        case "card_giftcard":
            return "gift.fill"
        case "business":
            return "building.2.fill"
            
        // Health / Beauty
        case "spa":
            return "leaf.fill"
        case "medical_services":
            return "cross.case.fill"
        case "fitness_center":
            return "figure.strengthtraining.traditional"
        case "content_cut":
            return "scissors"
            
        // Vehicles / Transport
        case "directions_car", "car_repair":
            return "car.fill"
        case "commute":
            return "tram.fill"
        case "luggage":
            return "suitcase.fill"
            
        // Tech / Electronics
        case "computer":
            return "desktopcomputer"
        case "smartphone":
            return "iphone"
            
        // Outdoor / Leisure
        case "pedal_bike":
            return "bicycle"
        case "pool":
            return "figure.pool.swim"
        case "grass":
            return "leaf.arrow.circlepath"
            
        // Education / Work
        case "school":
            return "graduationcap.fill"
        case "group":
            return "person.3.fill"
        case "engineering":
            return "wrench.and.screwdriver.fill"
        case "design_services":
            return "paintbrush.fill"
        case "palette":
            return "paintpalette.fill"
            
        // Misc
        case "visibility":
            return "eye.fill"
        case "question_mark":
            return "questionmark.circle.fill"
        case "liquor":
            return "wineglass"
        case "sports_soccer":
            return "soccerball"
        case "vaping_rooms":
            return "smoke.fill"
            
        default:
            return "mappin.circle.fill"
        }
    }
        
    func categoryDescription() -> String {
        
        switch self {
            
        // Food & Drink
        case "local_cafe":
            return "Café"
        case "restaurant", "local_dining":
            return "Restaurant"
        case "lunch_dining":
            return "Eatery"
        case "local_pizza":
            return "Pizza place"
        case "local_bar":
            return "Bar"
        case "sports_bar":
            return "Sports bar"
        case "cake":
            return "Bakery"
        case "icecream":
            return "Ice cream shop"
        case "liquor":
            return "Liquor store"
            
        // Stay
        case "hotel":
            return "Hotel"
        case "cottage":
            return "Accommodation"
            
        // Bitcoin / Finance
        case "local_atm":
            return "Bitcoin ATM"
        case "account_balance":
            return "Financial services"
            
        // Retail
        case "shopping_cart", "store", "supermarket":
            return "Shop"
        case "storefront":
            return "Store"
        case "local_grocery_store":
            return "Grocery store"
        case "card_giftcard":
            return "Gift shop"
        case "business":
            return "Business"
            
        // Health / Beauty
        case "spa":
            return "Spa"
        case "medical_services":
            return "Medical services"
        case "fitness_center":
            return "Gym"
        case "content_cut":
            return "Hairdresser"
            
        // Vehicles / Transport
        case "directions_car":
            return "Car dealer"
        case "car_repair":
            return "Car repair"
        case "commute":
            return "Transport"
        case "luggage":
            return "Travel services"
            
        // Tech
        case "computer":
            return "Computer store"
        case "smartphone":
            return "Phone shop"
            
        // Outdoor / Leisure
        case "pedal_bike":
            return "Bike shop"
        case "pool":
            return "Watersports"
        case "grass":
            return "Garden services"
            
        // Education / Work
        case "school":
            return "School"
        case "group":
            return "Community"
        case "engineering":
            return "Engineering"
        case "design_services":
            return "Design services"
        case "palette":
            return "Art"
            
        // Misc
        case "visibility":
            return "Optical services"
        case "question_mark":
            return "Business"
        case "sports_soccer":
            return "Sports club"
        case "vaping_rooms":
            return "Vape shop"
            
        default:
            return "Business"
        }
    }
}
