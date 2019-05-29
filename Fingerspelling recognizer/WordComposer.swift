//
//  WordComposer.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 17/04/2019.
//  Copyright © 2019 aa. All rights reserved.
//

import Foundation

class WordComposer {

    struct CurrentLetter {
        enum Confidence {
            case low, medium, high
        }
        let letter: String
        let confidence: Confidence
    }
    
    private let alternateSymbols = ["2": "V",
                                    "6": "W"]
    
    private let framesBeforeRecognition = 8
    private let framesBetweenSameResults = 36

    private let bufferSize = 45
    private let spaceThrottler = Throttler(seconds: 1.6)
    private var currentLetterMeans: [String: Float] = [:]
    private var currentLetterResults: [String: CircularBuffer<Float>] = [:]
    private var sampleCount: Int = 0
    var currentText: String = ""
    var currentLetter: CurrentLetter?

    func add(classifications: [String: Float]) {
        let previousSampleCount = sampleCount
        sampleCount = min(bufferSize, sampleCount + 1)
        for (key, value) in classifications {
            if currentLetterResults[key] == nil {
                currentLetterResults[key] = CircularBuffer<Float>(capacity: bufferSize)
            }
            if currentLetterMeans[key] == nil {
                currentLetterMeans[key] = 0
            }
            if let replacedValue = currentLetterResults[key]!.addOrReplace(value: value) {
                currentLetterMeans[key] = currentLetterMeans[key]! - (replacedValue * replacedValue) / Float(previousSampleCount)
            }
            currentLetterMeans[key] = (currentLetterMeans[key]! * Float(previousSampleCount) + (value * value)) / Float(sampleCount)
        }
        updateCurrentLetter()
    }
    
    func clearClassifications() {
        currentLetter = nil
        currentLetterResults.removeAll()
        currentLetterMeans.removeAll()
        sampleCount = 0
        spaceThrottler.invalidate()
    }
    
    func removeLastLetter() {
        if !currentText.isEmpty {
            currentText.removeLast()
        }
    }

    private func updateCurrentLetter() {
        guard sampleCount > framesBeforeRecognition else { return }
        let maxConfidenceLetter = currentLetterMeans.max(by: { return $0.value < $1.value })!
        //print(maxConfidenceLetter, sampleCount)
        if maxConfidenceLetter.value > 0.96 - Float(sampleCount) * 0.003 {
            resetSpaceThrottler()
            // Reduce same results
            if let lastChar = currentText.last, String(lastChar) == maxConfidenceLetter.key, sampleCount < framesBetweenSameResults {
                return
            }
            append(letter: maxConfidenceLetter.key)
        } else if maxConfidenceLetter.value > 0.4 {
            let confidence: CurrentLetter.Confidence
            if maxConfidenceLetter.value > 0.6 {
                confidence = .medium
                resetSpaceThrottler()
            } else {
                confidence = .low
            }
            currentLetter = CurrentLetter(letter: maxConfidenceLetter.key,
                                          confidence: confidence)
        } else {
            currentLetter = nil
            if !spaceThrottler.isValid {
                resetSpaceThrottler()
            }
        }
    }
    
    private func append(letter: String) {
        defer { clearClassifications() }
        guard let lastSymbol = currentText.last.map(String.init) else {
            currentText.append(letter)
            return
        }
        
        let currentSymbol: String
        if let alternateLetter = alternateSymbols[letter] {
            if lastSymbol == " " || Int(lastSymbol) != nil {
                currentSymbol = letter
            } else {
                currentSymbol = alternateLetter
            }
        } else {
            currentSymbol = letter
        }
        
        if let lastSymbolAlternate = alternateSymbols[lastSymbol], Int(currentSymbol) == nil {
            currentText.removeLast()
            currentText.append(lastSymbolAlternate)
        }
        currentText.append(currentSymbol)
    }
    
    private func resetSpaceThrottler() {
        spaceThrottler.throttle { [weak self] in
            if let lastChar = self?.currentText.last, lastChar != " " {
                self?.currentText.append(" ")
            }
        }
    }
}
