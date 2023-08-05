//
//  AddressViewModel.swift
//  bittr
//
//  Created by Tom Melters on 25/07/2023.
//

import Foundation
import LDKNode

class AddressViewModel: ObservableObject {
    @Published var address: String = ""
    @Published var addressViewError: MondayError?
    @Published var isAddressFinished: Bool = false
    
    func newFundingAddress() async {
        do {
            let address = try await LightningNodeService.shared.newFundingAddress()
            DispatchQueue.main.async {
                self.address = address
                self.isAddressFinished = true
                
                let notificationDict:[String: Any] = ["address":address]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setnewaddress"), object: nil, userInfo: notificationDict) as Notification)
            }
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                self.addressViewError = .init(title: errorString.title, detail: errorString.detail)
            }
        } catch {
            DispatchQueue.main.async {
                self.addressViewError = .init(title: "Unexpected error", detail: error.localizedDescription)
            }
        }
    }
}
