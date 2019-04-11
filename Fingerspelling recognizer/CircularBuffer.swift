//
//  CircularBuffer.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 20/04/2019.
//  Copyright © 2019 aa. All rights reserved.
//

import Foundation

struct CircularBuffer<T> {

    private var internalArray: [T?]
    private var currentIndex = 0

    init(capacity: Int) {
        internalArray = [T?](repeating: nil, count: capacity)
    }

    mutating func addOrReplace(value: T) -> T? {
        let replacedValue = internalArray[currentIndex]
        internalArray[currentIndex] = value
        currentIndex = (currentIndex + 1) % internalArray.count
        return replacedValue
    }
}
