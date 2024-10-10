//
//  Language.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

class Language: NSObject {
    
    static func getWord(withID:String) -> String {
        
        if CacheManager.getLanguage() == "en_US" {
            return fromEnUS(withID: withID)
        } else {
            return ""
        }
    }
    
    static func fromEnUS(withID:String) -> String {
        
        let allWords:[String:String] = [
            "yourwallet": "your wallet",
            "syncing": "syncing",
            "send": "Send",
            "receive": "Receive",
            "buy": "Buy",
            "totalprofit": "Total profit",
            "notransactions1": "There are no transactions. Tap ",
            "notransactions2": " to get your first bitcoin.",
            "transaction": "transaction",
            "instant": "Instant",
            "regular": "Regular",
            "amount": "Amount",
            "type": "Type",
            "id": "ID",
            "description": "Description",
            "currentvalue": "Current value",
            "purchasevalue": "Purchase value",
            "profit": "Profit",
            "addanote": "Add a note",
            "feespaid": "Fees paid",
            "confirmations": "Confirmations",
            "sats": "sats",
            "news": "news",
            "questions": "questions",
            "noarticles": "There are no articles.",
            "getsupport": "Get support",
            "restorewallet": "Restore wallet",
            "privacypolicy": "Privacy Policy",
            "termsandconditions": "Terms & Conditions",
            "currency": "Currency",
            "walletandbalance": "Wallet and balance",
            "devicedetails": "Device details",
            "appversion": "App version",
            "enteryourpincode": "Enter your PIN code",
            "confirm": "Confirm",
            "setapin": "Set a PIN code for secure access to your wallet",
            "confirmyourpin": "Confirm your PIN code",
            "back": "Back",
            "next": "Next",
            "balance": "balance",
            "walletsubtitle": "These are the funds in your bitcoin wallet and bitcoin lightning channel.",
            "lightningchannels": "lightning channels",
            "lightningexplanation1": "To send and receive Bitcoin Lightning payments, you need to have at least one Lightning channel with anyone.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information.",
            "lightningchannel": "lightning channel",
            "lightningexplanation2": "To send and receive Bitcoin Lightning payments, you need to have at least one Lightning channel with anyone.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information.",
            "sendbitcoin": "send bitcoin",
            "sendtoplabel": "Send bitcoin from your bitcoin wallet to another bitcoin wallet. Scan a QR code or input manually.",
            "sendtoplabellightning": "Send bitcoin from your bitcoin lightning wallet to another bitcoin lightning wallet.",
            "address": "Address",
            "invoice": "Invoice",
            "sendall": "Send all",
            "youcansend": "You can send",
            "enterinvoice": "Enter invoice",
            "enteraddress": "Enter address",
            "enteramount": "Enter amount",
            "manualinput": "Manual input",
            "confirmtransaction": "confirm transaction",
            "checkdetails": "Make sure these details are correct.",
            "feerate": "Select your preferred fee rate.",
            "edit": "Edit",
            "limitlightning": "why a limit for instant payments?",
            "limitlightninganswer": "Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning channel (for instant payments).\n\nIf you've purchased satoshis into your lightning channel, you can use those to pay lightning invoices.\n\nYou cannot make instant payments that exceed the funds in your lightning channel.",
            "checkyourconnection": "Check your connection",
            "trytoconnect": "You don't seem to be connected to the internet. Please try to connect.",
            "okay": "Okay",
            "receivebitcoin": "receive bitcoin",
            "thisisanaddress": "This is an address to your bitcoin wallet.",
            "createaninvoice": "Create a Lightning invoice to receive bitcoin instantly to your Lightning wallet.",
            "amountinsatoshis": "Amount (in satoshis)",
            "youcanreceive": "You can receive up to",
            "enterdescription": "Enter description",
            "createinvoice": "Create invoice",
            "lightninginvoice": "lightning invoice",
            "thisisyourinvoice": "This is your Lightning invoice.",
            "done": "Done",
            "copied": "Copied",
            "theresalimit": "There's a limit to the amount of satoshis you can receive per invoice.\n\nYour bitcoin lightning channel has a size, ten times the amount of your first Bittr purchase. If the size is 10,000 sats and you've already purchased 2,000 sats, you can still receive up to 8,000 sats in total.\n\nPer invoice you can receive up to ten percent of the channel size. If you need more, you can create multiple invoices.\n\nWhen the channel is full, we empty the channel funds into your bitcoin wallet so that you have space again.",
            "oops": "Oops!",
            "addressfail": "We couldn't fetch a wallet address. Please try again.",
            "tryagain": "Try again",
            "addressfail2": "We couldn't fetch a wallet address",
            "pleasetryagain": "Please try again",
            "cancel": "Cancel",
            "unexpectederror": "Unexpected error",
            "error": "Error"
        ]
        
        if let foundWord = allWords[withID] {
            return foundWord
        } else {
            return ""
        }
    }
    
}
