//
//  StabilizationDetector.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 14/04/2019.
//  Copyright © 2019 aa. All rights reserved.
//

import Vision

protocol StabilizationDetectorDelegate: class {
    func sceneStabilityAchieved(at frame: CVPixelBuffer)
    func sceneStabilityNotAchieved()
}

enum SceneStabilaztionState {
    case stable
    case notStable
    case deleteChar
}

class StabilizationDetector {

    private let historyLength: Int
    private let stabilityThreshold: CGFloat

    private let sequenceRequestHandler = VNSequenceRequestHandler()
    private var transpositionHistoryPoints: [CGPoint] = []
    private var previousFrame: CVPixelBuffer?

    weak var delegate: StabilizationDetectorDelegate?

    init(historyLength: Int = 4,
         stabilityThreshold: CGFloat = 10) {
        self.historyLength = historyLength
        self.stabilityThreshold = stabilityThreshold
    }

    func sceneStabilityAchieved(newFrame: CVPixelBuffer) -> Bool {
        defer { previousFrame = newFrame }
        guard previousFrame != nil else {
            return false
        }

        let registrationRequest = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: newFrame)
        do {
            try sequenceRequestHandler.perform([registrationRequest], on: previousFrame!)
        } catch let error as NSError {
            print("StabilizationDetector: failed to process request: \(error.localizedDescription).")
            return false
        }

        if let results = registrationRequest.results,
           let alignmentObservation = results.first as? VNImageTranslationAlignmentObservation {
            let alignmentTransform = alignmentObservation.alignmentTransform
            add(transposition: CGPoint(x: alignmentTransform.tx, y: alignmentTransform.ty))
            if sceneStabilityAchieved() {
                delegate?.sceneStabilityAchieved(at: newFrame)
                return true
            } else {
                delegate?.sceneStabilityNotAchieved()
            }
        }
        return false
    }

    private func sceneStabilityAchieved() -> Bool {
        if transpositionHistoryPoints.count == historyLength {
            var movingAverage: CGPoint = CGPoint.zero
            transpositionHistoryPoints.forEach {
                movingAverage.x += $0.x
                movingAverage.y += $0.y
            }
            let distance = abs(movingAverage.x) + abs(movingAverage.y)
            print("stabilization distance: \(movingAverage)")
            if distance < stabilityThreshold {
                return true
            }
        }
        return false
    }

    private func add(transposition: CGPoint) {
        transpositionHistoryPoints.append(transposition)

        if transpositionHistoryPoints.count > historyLength {
            transpositionHistoryPoints.removeFirst()
        }
    }
}
