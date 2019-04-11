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

    private let bufferSize = 45
    private var currentLetterMeans: [String: Float] = [:]
    private var currentLetterResults: [String: CircularBuffer<Float>] = [:]
    private var sampleCount: Int = 0
    var currentWord: String = ""
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
            if let replacedValue = currentLetterResults[key]?.addOrReplace(value: value) {
                currentLetterMeans[key] = currentLetterMeans[key]! - (replacedValue * replacedValue) / Float(sampleCount)
            }
            currentLetterMeans[key] = (currentLetterMeans[key]! * Float(previousSampleCount) + (value * value)) / Float(sampleCount)
        }
        updateCurrentLetter()
    }

    func addLetterBreak() {
        guard sampleCount > 8 else { return }
        let maxConfidenceLetter = currentLetterMeans.max(by: { return $0.value < $1.value })!
        if maxConfidenceLetter.value > 0.94 - Float(sampleCount) * 0.003 {
            currentWord.append(maxConfidenceLetter.key)
        }
        print(maxConfidenceLetter.key, maxConfidenceLetter.value / Float(sampleCount), sampleCount)
        currentLetter = nil
        currentLetterResults.removeAll()
        currentLetterMeans.removeAll()
        sampleCount = 0
    }

    private func updateCurrentLetter() {
        guard sampleCount > 8 else { return }
        let maxConfidenceLetter = currentLetterMeans.max(by: { return $0.value < $1.value })!
        let confidence: CurrentLetter.Confidence
        if maxConfidenceLetter.value > 0.94 - Float(sampleCount) * 0.004 {
            confidence = .high
        } else if maxConfidenceLetter.value > 0.6 {
            confidence = .medium
        } else {
            confidence = .low
        }
        currentLetter = CurrentLetter(letter: maxConfidenceLetter.key,
                                      confidence: confidence)
    }
}
