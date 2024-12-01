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
            if darkModeIsOn {return self.returnColor("blue1", 0.5)}
            else {return UIColor.white}
        case "transparentbutton":
            if darkModeIsOn {return self.returnColor("blue1", 0.5)}
            else {return self.returnColor("white", 0.7)}
        case "lighterbutton":
            if darkModeIsOn {return self.returnColor("blue2", 1.0)}
            else {return self.returnColor("white", 0.7)}
        case "cardview":
            if darkModeIsOn {return self.returnColor("blue2", 1.0)}
            else {return UIColor.white}
        case "cardbackground":
            if darkModeIsOn {return self.returnColor( "blue2", 1.0)}
            else {return self.returnColor("yellow", 1.0)}
        case "whiteorlightblue":
            if darkModeIsOn {return self.returnColor( "blue3", 1.0)}
            else {return self.returnColor("white", 1.0)}
        case "black":
            if darkModeIsOn {return UIColor.white} 
            else {return UIColor.black}
        case "grey":
            if darkModeIsOn {return self.returnColor("blue1", 1.0)}
            else {return self.returnColor("darkgrey", 1.0)}
        case "yellow":
            if darkModeIsOn {return self.returnColor("blue3", 1.0)}
            else {return self.returnColor("yellow", 1.0)}
        case "yellowandgrey":
            if darkModeIsOn {return self.returnColor("blue1", 1.0)}
            else {return self.returnColor("yellow", 1.0)}
        case "transparentyellow":
            if darkModeIsOn {return self.returnColor("blue3", 0.85)}
            else {return self.returnColor("yellow", 0.85)}
        case "dateview":
            if darkModeIsOn {return self.returnColor("blue3", 1.0)}
            else {return self.returnColor("grey1", 1.0)}
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
            if darkModeIsOn {return self.returnColor("white", 0.5)}
            else {return UIColor(red: 177/255, green: 177/255, blue: 177/255, alpha: 1)}
        case "transparentblack":
            if darkModeIsOn {return self.returnColor("white", 0.5)}
            else {return self.returnColor("black", 0.5)}
        case "appversion":
            if darkModeIsOn {return self.returnColor("white", 0.5)}
            else {return self.returnColor("black", 0.25)}
        case "blackbutton":
            if darkModeIsOn {return self.returnColor("blue1", 1.0)}
            else {return UIColor.black}
            
        case "yelloworblue1":
            if darkModeIsOn {return self.returnColor("blue1", 1.0)}
            else {return self.returnColor("yellow", 1.0)}
        case "yelloworblue2":
            if darkModeIsOn {return self.returnColor("blue2", 1.0)}
            else {return self.returnColor("yellow", 1.0)}
        case "yelloworblue3":
            if darkModeIsOn {return self.returnColor("blue3", 1.0)}
            else {return self.returnColor("yellow", 1.0)}
            
        case "whiteorblue2":
            if darkModeIsOn {return self.returnColor("blue2", 1.0)}
            else {return self.returnColor("white", 1.0)}
        case "white0.7orblue2":
            if darkModeIsOn {return self.returnColor("blue2", 1.0)}
            else {return self.returnColor("white", 0.7)}
        case "whiteorblue3":
            if darkModeIsOn {return self.returnColor("blue3", 1.0)}
            else {return self.returnColor("white", 1.0)}
            
        case "grey1orblue3":
            if darkModeIsOn {return self.returnColor("blue3", 1.0)}
            else {return self.returnColor("grey1", 1.0)}
        case "grey2orwhite":
            if darkModeIsOn {return self.returnColor("white", 1.0)}
            else {return self.returnColor("grey2", 1.0)}
        case "grey2orwhite0.7":
            if darkModeIsOn {return self.returnColor("white", 0.7)}
            else {return self.returnColor("grey2", 1.0)}
            
        case "blackorwhite":
            if darkModeIsOn {return UIColor.white}
            else {return UIColor.black}
        case "black0.5orwhite0.5":
            if darkModeIsOn {return self.returnColor("white", 0.5)}
            else {return self.returnColor("black", 0.5)}
        case "blackoryellow":
            if darkModeIsOn {return self.returnColor("yellow", 1.0)}
            else {return self.returnColor("black", 1.0)}
            
        default:
            return UIColor.white
        }
    }
    
    static func returnColor(_ color:String, _ opacity:CGFloat) -> UIColor {
        
        switch color {
            
        case "blue1": return UIColor(displayP3Red: 50/255, green: 92/255, blue: 140/255, alpha: opacity)
        case "blue2": return UIColor(displayP3Red: 72/255, green: 113/255, blue: 157/255, alpha: opacity)
        case "blue3": return UIColor(displayP3Red: 113/255, green: 143/255, blue: 179/255, alpha: opacity)
        case "darkgrey": return UIColor(displayP3Red: 252/255, green: 252/255, blue: 255/255, alpha: opacity)
        case "yellow": return UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: opacity)
        case "white": return UIColor(displayP3Red: 1, green: 1, blue: 1, alpha: opacity)
        case "black": return UIColor(displayP3Red: 0, green: 0, blue: 0, alpha: opacity)
        case "grey1": return UIColor(displayP3Red: 237/255, green: 243/255, blue: 247/255, alpha: opacity)
        case "grey2": return UIColor(displayP3Red: 157/255, green: 161/255, blue: 172/255, alpha: opacity)
        
        default: return UIColor(displayP3Red: 50/255, green: 92/255, blue: 140/255, alpha: opacity)
        }
    }
    
}
