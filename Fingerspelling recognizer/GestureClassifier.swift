//
//  GestureClassifier.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 16/04/2019.
//  Copyright © 2019 aa. All rights reserved.
//

import Vision
import UIKit

protocol GestureClassifierDelegate: class {
    func recognized(results: [String: Float])
}

class GestureClassifier {

    private let processingQueue = DispatchQueue(label: "aa.fingerspellingRecognizer.visionQueue")
    private var visionRequest: VNCoreMLRequest!
    private var currentProcessedImage: CGImage?

    weak var delegate: GestureClassifierDelegate?

    init() {
        let model = try! VNCoreMLModel(for: fingerspelling_recognizer_new().model)
        visionRequest = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
            self?.processClassifications(for: request, error: error)
        })
        visionRequest.imageCropAndScaleOption = .scaleFit
    }

    func recognize(image: CGImage) {
        guard currentProcessedImage == nil else { return }
        currentProcessedImage = image
        let aspect = CGFloat(image.height) / CGFloat(image.width)
        if 0.92 < aspect && aspect < 1.08 {
            visionRequest.imageCropAndScaleOption = .scaleFill
        } else {
            visionRequest.imageCropAndScaleOption = .scaleFit
        }
        processingQueue.async {
            defer { self.currentProcessedImage = nil }
            let handler = VNImageRequestHandler(cgImage: image, orientation: GestureClassifier.exifOrientationFromDeviceOrientation())
            do {
                try handler.perform([self.visionRequest])
            } catch {
                print("Failed to perform classification. \(error.localizedDescription)")
            }
        }
    }

    private func processClassifications(for request: VNRequest, error: Error?) {
        guard let results = request.results else {
            print("Vision request failed. \(error?.localizedDescription ?? "")")
            return
        }
        let classifications = results as! [VNClassificationObservation]
        //print(classifications.map({String(format: "(%.2f) %@", $0.confidence, $0.identifier)}))
        let dict = [String: Float](uniqueKeysWithValues: classifications.map { ($0.identifier, $0.confidence) })
        delegate?.recognized(results: dict)
    }

    static func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation

        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }
}
