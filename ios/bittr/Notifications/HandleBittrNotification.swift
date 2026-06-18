//
//  HandleBittrNotification.swift
//  bittr
//
//  Created by Tom Melters on 21/03/2024.
//

import UIKit

extension CoreViewController {

    func handleBittrNotification(_ notification:BittrNotification) {
        
        // Show to the user information that was received from a Bittr push notification.
        self.launchQuestion(question: notification.headerText ?? Language.getWord(withID: "oops"), answer: notification.bodyText ?? Language.getWord(withID: "bittrnotificationfail"), type: nil)
    }

}
