//
//  Component.swift
//  bittr
//
//  Created by Tom Melters on 10/21/25.
//

import UIKit

class Component: NSObject {
    
    var type: ComponentType = .label
    var text: String = ""
    var url: String = ""
    var order: Int = 0
}

enum ComponentType {
    case label
    case image
}
