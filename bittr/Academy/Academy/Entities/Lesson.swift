//
//  Lesson.swift
//  bittr
//
//  Created by Tom Melters on 10/21/25.
//

import UIKit

class Lesson: NSObject {
    
    var id: String = ""
    var order: Int = 0
    var title: String = ""
    var pages = [Page]()
    var image: String?
}
