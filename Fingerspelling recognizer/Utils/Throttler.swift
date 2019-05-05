//
//  Throttler.swift
//  Fingerspelling recognizer
//
//  Created by Артур Антонов on 03.05.2019.
//  Copyright © 2019 aa. All rights reserved.
//

import Foundation

class Throttler {
    
    private let queue: DispatchQueue = DispatchQueue.main
    
    private var job: DispatchWorkItem?
    private var previousRun: Date = Date.distantPast
    private var delay: Double
    
    var isValid: Bool {
        get {
            return job != nil
        }
    }
    
    init(seconds: Double) {
        self.delay = seconds
    }
    
    func throttle(block: @escaping () -> ()) {
        job?.cancel()
        job = DispatchWorkItem(){ [weak self] in
            self?.previousRun = Date()
            block()
        }
        queue.asyncAfter(deadline: .now() + delay, execute: job!)
    }
    
    func invalidate() {
        job?.cancel()
        job = nil
    }
}
