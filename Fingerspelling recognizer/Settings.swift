//
//  Settings.swift
//  Fingerspelling recognizer
//
//  Created by Артур Антонов on 02.05.2019.
//  Copyright © 2019 aa. All rights reserved.
//

import Foundation

class Settings {
    
    private static let storage = UserDefaults.standard
    
    static var autodetectHand: Bool {
        get {
            return storage.bool(forKey: "autodetectHand")
        }
        set {
            storage.set(newValue, forKey: "autodetectHand")
        }
    }
    
    static var framesBeforeRecongition: Int {
        get {
            return storage.integer(forKey: "framesBeforeRecongition")
        }
        set {
            storage.set(newValue, forKey: "framesBeforeRecongition")
        }
    }
}
