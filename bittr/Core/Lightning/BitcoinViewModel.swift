//
//  BitcoinViewModel.swift
//  bittr
//
//  Created by Tom Melters on 09/08/2023.
//

import UIKit
import LDKNode

class BitcoinViewModel: ObservableObject {

    @Published var balance: String = "0"
    @Published var bitcoinViewError: MondayError?
    @Published var spendableBalance: String = "0"
    @Published var totalBalance: String = "0"
    @Published var isSpendableBalanceFinished: Bool = false
    @Published var isTotalBalanceFinished: Bool = false
    
    func getTotalOnchainBalanceSats() async {
        do {
            let balance = try await LightningNodeService.shared.getTotalOnchainBalanceSats()
            let intBalance = Int(balance)
            let stringIntBalance = String(intBalance)
            DispatchQueue.main.async {
                self.totalBalance = stringIntBalance
                self.isTotalBalanceFinished = true
                let notificationDict:[String: Any] = ["balance":stringIntBalance]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "settotalsats"), object: nil, userInfo: notificationDict) as Notification)
            }
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                self.bitcoinViewError = .init(title: errorString.title, detail: errorString.detail)
            }
        } catch {
            DispatchQueue.main.async {
                self.bitcoinViewError = .init(title: "Unexpected error", detail: error.localizedDescription)
            }
        }
    }
}
