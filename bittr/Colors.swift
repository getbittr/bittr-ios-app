//
//  Colors.swift
//  bittr
//
//  Created by Tom Melters on 13/08/2024.
//

import UIKit

class Colors: NSObject {

    static func getColor(color:String) -> UIColor {
        
        let darkModeIsOn = CacheManager.darkModeIsOn()
        
        switch color {
        case "headerview":
            if darkModeIsOn {return self.returnColor(color:"darkblue", opacity: 0.5)}
            else {return UIColor.white}
        case "transparentbutton":
            if darkModeIsOn {return self.returnColor(color:"darkblue", opacity: 0.5)}
            else {return self.returnColor(color:"white", opacity: 0.7)}
        case "lighterbutton":
            if darkModeIsOn {return self.returnColor(color:"lightblue", opacity: 0.4)}
            else {return self.returnColor(color:"white", opacity: 0.7)}
        case "cardview":
            if darkModeIsOn {return self.returnColor(color:"lightblue", opacity: 0.4)}
            else {return UIColor.white}
        case "cardbackground":
            if darkModeIsOn {return self.returnColor(color: "lightblue", opacity: 0.4)}
            else {return self.returnColor(color:"yellow", opacity: 1.0)}
        case "whiteorlightblue":
            if darkModeIsOn {return self.returnColor(color: "lightblue", opacity: 1.0)}
            else {return self.returnColor(color:"white", opacity: 1.0)}
        case "black":
            if darkModeIsOn {return UIColor.white} 
            else {return UIColor.black}
        case "grey":
            if darkModeIsOn {return self.returnColor(color:"darkblue", opacity: 1.0)}
            else {return self.returnColor(color:"darkgrey", opacity: 1.0)}
        case "yellow":
            if darkModeIsOn {return self.returnColor(color:"lightblue", opacity: 1.0)}
            else {return self.returnColor(color:"yellow", opacity: 1.0)}
        case "yellowandgrey":
            if darkModeIsOn {return self.returnColor(color:"darkblue", opacity: 1.0)}
            else {return self.returnColor(color:"yellow", opacity: 1.0)}
        case "transparentyellow":
            if darkModeIsOn {return self.returnColor(color:"lightblue", opacity: 0.85)}
            else {return self.returnColor(color:"yellow", opacity: 0.85)}
        case "dateview":
            if darkModeIsOn {return self.returnColor(color:"lightblue", opacity: 1.0)}
            else {return self.returnColor(color:"lightgrey", opacity: 1.0)}
        case "lossbackground":
            if darkModeIsOn {return UIColor(red: 255/255, green: 59/255, blue: 48/255, alpha: 0.3)}
            else {return UIColor(red: 255/255, green: 237/255, blue: 237/255, alpha: 1)}
        case "profitbackground":
            if darkModeIsOn {return UIColor(red: 81/255, green: 152/255, blue: 73/255, alpha: 0.6)}
            else {return UIColor(red: 231/255, green: 248/255, blue: 229/255, alpha: 1)}
        case "losstext":
            if darkModeIsOn {return UIColor(red: 255/255, green: 237/255, blue: 237/255, alpha: 1)}
            else {return UIColor(red: 199/255, green: 142/255, blue: 142/255, alpha: 1)}
        case "profittext":
            if darkModeIsOn {return UIColor(red: 231/255, green: 248/255, blue: 229/255, alpha: 1)}
            else {return UIColor(red: 81/255, green: 152/255, blue: 73/255, alpha: 1)}
        case "unconfirmed":
            if darkModeIsOn {return self.returnColor(color:"white", opacity: 0.5)}
            else {return UIColor(red: 177/255, green: 177/255, blue: 177/255, alpha: 1)}
        case "transparentblack":
            if darkModeIsOn {return self.returnColor(color:"white", opacity: 0.5)}
            else {return self.returnColor(color:"black", opacity: 0.5)}
        case "appversion":
            if darkModeIsOn {return self.returnColor(color:"white", opacity: 0.5)}
            else {return self.returnColor(color:"white", opacity: 0.25)}
        case "blackbutton":
            if darkModeIsOn {return self.returnColor(color: "darkblue", opacity: 1.0)}
            else {return UIColor.black}
        default:
            return UIColor.white
        }
    }
    
    static func returnColor(color:String, opacity:CGFloat) -> UIColor {
        switch color {
        case "darkblue": return UIColor(red: 50/255, green: 92/255, blue: 140/255, alpha: opacity)
        case "darkgrey": return UIColor(red: 252/255, green: 252/255, blue: 255/255, alpha: opacity)
        case "yellow": return UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: opacity)
        case "lightblue": return UIColor(displayP3Red: 113/255, green: 143/255, blue: 179/255, alpha: opacity)
        case "white": return UIColor(red: 1, green: 1, blue: 1, alpha: opacity)
        case "black": return UIColor(red: 0, green: 0, blue: 0, alpha: opacity)
        case "lightgrey": return UIColor(red: 237/255, green: 243/255, blue: 247/255, alpha: opacity)
        default: return UIColor(red: 50/255, green: 92/255, blue: 140/255, alpha: opacity)
        }
    }
    
}
