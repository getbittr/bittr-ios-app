//
//  CacheManager.swift
//  bittr
//
//  Created by Tom Melters on 24/06/2023.
//

import UIKit

class CacheManager: NSObject {

    
    static func deleteClientInfo() {
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "device")
    }
    
    
    static func parseDevice(deviceDict:NSDictionary) -> [Client] {
        
        var allClients = [Client]()
        
        for (clientid, clientdata) in deviceDict {
            
            let client = Client()
            
            if let actualClientDict = clientdata as? NSDictionary {
                
                if let actualClientID = clientid as? String {
                    client.id = actualClientID
                }
                if let actualClientOrder = actualClientDict["order"] as? Int {
                    client.order = actualClientOrder
                }
                var ibansInClient = [IbanEntity]()
                if let actualIbansDict = actualClientDict["ibans"] as? NSDictionary {
                    
                    for (ibanid, ibandata) in actualIbansDict {
                        
                        let iban = IbanEntity()
                        
                        if let ibanDataDict = ibandata as? NSDictionary {
                            
                            if let actualIbanID = ibanid as? String {
                                iban.id = actualIbanID
                            }
                            if let actualYourIban = ibanDataDict["youriban"] as? String {
                                iban.yourIbanNumber = actualYourIban
                            }
                            if let actualYourEmail = ibanDataDict["youremail"] as? String {
                                iban.yourEmail = actualYourEmail
                            }
                            if let actualYourCode = ibanDataDict["yourcode"] as? String {
                                iban.yourUniqueCode = actualYourCode
                            }
                            if let actualOurIban = ibanDataDict["ouriban"] as? String {
                                iban.ourIbanNumber = actualOurIban
                            }
                            if let actualOurName = ibanDataDict["ourname"] as? String {
                                iban.ourName = actualOurName
                            }
                            if let actualIbanOrder = ibanDataDict["order"] as? Int {
                                iban.order = actualIbanOrder
                            }
                            if let actualIbanToken = ibanDataDict["token"] as? String {
                                iban.emailToken = actualIbanToken
                            }
                            
                            ibansInClient += [iban]
                        }
                    }
                    
                    client.ibanEntities = ibansInClient
                    client.ibanEntities.sort { iban1, iban2 in
                        iban1.order < iban2.order
                    }
                }
            }
            
            allClients += [client]
        }
        
        allClients.sort { client1, client2 in
            client1.order < client2.order
        }
        
        return allClients
    }
    
    
    static func addIban(clientID:String,iban:IbanEntity) {
        
        let clientsDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        
        if let actualClientsDict = clientsDict {
            // At least one client already exists.
            let clients = self.parseDevice(deviceDict: actualClientsDict)
            for client in clients {
                if client.id == clientID {
                    var ibanExists = false
                    for existingIban in client.ibanEntities {
                        if existingIban.id == iban.id {
                            ibanExists = true
                            existingIban.yourIbanNumber = iban.yourIbanNumber
                            existingIban.yourEmail = iban.yourEmail
                        }
                    }
                    if ibanExists == false {
                        // This is a new IBAN entity.
                        client.ibanEntities += [iban]
                    }
                }
            }
            
            var updatedClientsDict = NSMutableDictionary()
            for client in clients {
                var ibansDict = NSMutableDictionary()
                for existingIban in client.ibanEntities {
                    ibansDict.setObject(["order":existingIban.order,"youriban":existingIban.yourIbanNumber, "youremail":existingIban.yourEmail, "yourcode":existingIban.yourUniqueCode, "ouriban":existingIban.ourIbanNumber, "ourname":existingIban.ourName, "token":existingIban.emailToken, "ourswift":existingIban.ourSwift], forKey: existingIban.id as NSCopying)
                }
                updatedClientsDict.setObject(["order":client.order, "ibans":ibansDict], forKey: client.id as NSCopying)
            }
            UserDefaults.standard.set(updatedClientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        } else {
            // No clients have been added yet.
            let client = Client()
            client.id = clientID
            client.order = 0
            client.ibanEntities += [iban]
            
            let clientsDict:NSDictionary = [client.id:["order":client.order,"ibans":[iban.id:["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken]]]]
            UserDefaults.standard.set(clientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        }
    }
    
    static func addEmailToken(clientID:String, ibanID:String, emailToken:String) {
        
        let clientsDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        if let actualClientsDict = clientsDict {
            
            let clients = self.parseDevice(deviceDict: actualClientsDict)
            
            for client in clients {
                if client.id == clientID {
                    for iban in client.ibanEntities {
                        if iban.id == ibanID {
                            iban.emailToken = emailToken
                        }
                    }
                }
            }
            
            var updatedClientsDict = NSMutableDictionary()
            for client in clients {
                var ibansDict = NSMutableDictionary()
                for iban in client.ibanEntities {
                    ibansDict.setObject(["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken, "ourswift":iban.ourSwift], forKey: iban.id as NSCopying)
                }
                updatedClientsDict.setObject(["order":client.order, "ibans":ibansDict], forKey: client.id as NSCopying)
            }
            UserDefaults.standard.set(updatedClientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        }
    }
    
    static func addBittrIban(clientID:String, ibanID:String, ourIban:String, ourSwift:String, yourCode:String) {
        
        let clientsDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        if let actualClientsDict = clientsDict {
            
            let clients = self.parseDevice(deviceDict: actualClientsDict)
            
            for client in clients {
                if client.id == clientID {
                    for iban in client.ibanEntities {
                        if iban.id == ibanID {
                            iban.ourIbanNumber = ourIban
                            iban.yourUniqueCode = yourCode
                            iban.ourSwift = ourSwift
                        }
                    }
                }
            }
            
            var updatedClientsDict = NSMutableDictionary()
            for client in clients {
                var ibansDict = NSMutableDictionary()
                for iban in client.ibanEntities {
                    ibansDict.setObject(["order":iban.order,"youriban":iban.yourIbanNumber, "youremail":iban.yourEmail, "yourcode":iban.yourUniqueCode, "ouriban":iban.ourIbanNumber, "ourname":iban.ourName, "token":iban.emailToken, "ourswift":iban.ourSwift], forKey: iban.id as NSCopying)
                }
                updatedClientsDict.setObject(["order":client.order, "ibans":ibansDict], forKey: client.id as NSCopying)
            }
            UserDefaults.standard.set(updatedClientsDict, forKey: "device")
            UserDefaults.standard.synchronize()
        }
    }
    
    
    static func storeImageInCache(key:String, data:Data) {
        let defaults = UserDefaults.standard
        var existingImages = defaults.value(forKey: "articleimages") as? [String:Data]
        if var actualExistingImages = existingImages {
            // Images have already been stored.
            actualExistingImages.updateValue(data, forKey: key)
            defaults.set(actualExistingImages, forKey: "articleimages")
        } else {
            // No images have been stored yet.
            var newExistingImages = [String:Data]()
            newExistingImages.updateValue(data, forKey: key)
            defaults.set(newExistingImages, forKey: "articleimages")
        }
    }
    
    
    static func getImage(key:String) -> Data {
        
        let defaults = UserDefaults.standard
        var existingImages = defaults.value(forKey: "articleimages") as? [String:Data]
        
        if let actualExistingImages = existingImages {
            if let actualImage = actualExistingImages[key] {
                return actualImage
            }
        }
        
        return Data()
    }
    
    
}
