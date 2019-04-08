//
//  ViewController.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 24.01.2019.
//  Copyright © 2019 aa. All rights reserved.
//

import UIKit
import AVFoundation
import CoreVideo
import Photos
import Vision

class ViewController: UIViewController, CaptureSessionDelegate {

    private var session: CaptureSession!

    private var renderingEnabled = true

    private var visionRequest: VNCoreMLRequest!

    private var statusBarOrientation: UIInterfaceOrientation = .portrait

    private var depthCutOff: Float = 0.15

    private let imageView = UIImageView()
    private let slider = UISlider()
    private var frame = 3

    private let cutOffLabel = UILabel()
    private let classificationLabel = UILabel()
    let handRect = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = try! VNCoreMLModel(for: Fingerspelling().model)
        visionRequest = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
            self?.processClassifications(for: request, error: error)
        })
        visionRequest.imageCropAndScaleOption = .scaleFill

        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
            break

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                self.setupSession()
            })
        default:
            break
        }

        imageView.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        view.addSubview(imageView)
        slider.minimumValue = 0.05
        slider.maximumValue = 0.5
        slider.value = depthCutOff
        view.addSubview(slider)
        cutOffLabel.font = UIFont.systemFont(ofSize: 24)
        cutOffLabel.textColor = .red
        cutOffLabel.textAlignment = .center
        view.addSubview(cutOffLabel)

        classificationLabel.font = UIFont.systemFont(ofSize: 18)
        classificationLabel.textColor = .blue
        classificationLabel.numberOfLines = 0
        view.addSubview(classificationLabel)

        handRect.backgroundColor = .clear
        handRect.layer.borderColor = UIColor.green.cgColor
        handRect.layer.borderWidth = 4
        imageView.addSubview(handRect)
    }

    func setupSession() {
        session = CaptureSession()
        session.delegate = self
        session.startSession()
    }

    func processClassifications(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                self.classificationLabel.text = "Unable to classify image.\n\(error!.localizedDescription)"
                return
            }
            // The `results` will always be `VNClassificationObservation`s, as specified by the Core ML model in this project.
            let classifications = results as! [VNClassificationObservation]
            print(classifications.map({String(format: "(%.2f) %@", $0.confidence, $0.identifier)}))

            if classifications.isEmpty {
                self.classificationLabel.text = "Nothing recognized."
            } else {
                // Display top classifications ranked by confidence in the UI.
                let topClassifications = classifications.prefix(2)
                let descriptions = topClassifications.map { classification in
                    // Formats the classification for display; e.g. "(0.37) cliff, drop, drop-off".
                    return String(format: "  (%.2f) %@", classification.confidence, classification.identifier)
                }
                self.classificationLabel.text = descriptions.joined(separator: "\n")
            }
        }
    }

    override func viewDidLayoutSubviews() {
        imageView.frame = view.bounds.inset(by: view.safeAreaInsets)
        slider.frame = CGRect(x: 40, y: view.bounds.height - 70, width: view.bounds.width - 80, height: 50)
        cutOffLabel.frame = CGRect(x: 40, y: view.bounds.height - 140, width: view.bounds.width - 80, height: 50)
        classificationLabel.frame = CGRect(x: 40, y: view.bounds.height - 200, width: view.bounds.width - 80, height: 60)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        statusBarOrientation = interfaceOrientation

        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        session.stopSession()
        super.viewWillDisappear(animated)
    }

    func didOutputSynchronizedData(syncedDepthData: AVCaptureSynchronizedDepthData, syncedVideoData: AVCaptureSynchronizedSampleBufferData) {

        let depthPixelBuffer = syncedDepthData.depthData.depthDataMap
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(syncedVideoData.sampleBuffer) else {
            return
        }

//        frame = (frame + 1) % 4
//        if frame != 0 {
//            return
//        }

        // Convert depth map in-place: every pixel above cutoff is converted to 1. otherwise it's 0
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)

        CVPixelBufferLockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)

        var minsHeap = Heap<(Float, Int)>(sort: { return $0.0 > $1.0})

        for yMap in 0 ..< depthHeight {
            let rowData = baseAddress + yMap * bytesPerRow
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            for index in 0 ..< depthWidth {
                if minsHeap.count < 10 {
                    minsHeap.insert((data[index], yMap * depthWidth + index))
                } else if data[index] < minsHeap.peek()!.0 {
                    minsHeap.replace(index: 0, value: (data[index], yMap * depthWidth + index))
                }
            }
        }

        let (minDepth, mini) = minsHeap.peek()!
        let startPoint: (Int, Int) = (mini - (mini/depthWidth) * depthWidth, mini/depthWidth)
        let cutOff = minDepth + depthCutOff
        var pointsToExplore: [(Int, Int)] = [startPoint]
        var used = [[Bool]](repeating: [Bool](repeating: false, count: depthHeight), count: depthWidth)
        used[startPoint.0][startPoint.1] = true
        var minX = startPoint.0
        var maxX = startPoint.0
        var minY = startPoint.1
        var maxY = startPoint.1

        func depthData(at point: (Int, Int)) -> Float {
            let rowData = baseAddress + point.1 * bytesPerRow
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            return data[point.0]
        }

        while !pointsToExplore.isEmpty {
            let point = pointsToExplore.remove(at: 0)
            minX = min(minX, point.0)
            maxX = max(maxX, point.0)
            minY = min(minY, point.1)
            maxY = max(maxY, point.1)
            var neighbours: [(Int, Int)] = []
            if point.0 > 0 {
                if !used[point.0 - 1][point.1] {
                    used[point.0 - 1][point.1] = true
                    neighbours.append((point.0 - 1, point.1))
                }
            }
            if point.0 < depthWidth - 1 {
                if !used[point.0 + 1][point.1] {
                    used[point.0 + 1][point.1] = true
                    neighbours.append((point.0 + 1, point.1))
                }
            }
            if point.1 > 0 {
                if !used[point.0][point.1 - 1] {
                    used[point.0][point.1 - 1] = true
                    neighbours.append((point.0, point.1 - 1))
                }
            }
            if point.1 < depthHeight - 1 {
                if !used[point.0][point.1 + 1] {
                    used[point.0][point.1 + 1] = true
                    neighbours.append((point.0, point.1 + 1))
                }
            }

            for neighbour in neighbours {
                if depthData(at: neighbour) < cutOff {
                    pointsToExplore.append(neighbour)
                }
            }
        }

        var handRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: 0, dy: -10)
            .intersection(CGRect(x: 0, y: 0, width: depthWidth, height: depthHeight))
        if handRect.width/handRect.height > 1.5 {
            handRect.size.width = (1.5 * handRect.height).rounded()
        }

        var grayImage = [UInt8](repeating: 0, count: depthWidth * depthHeight)
        var classImage = [UInt8](repeating: 0, count: Int(handRect.width * handRect.height) * 4)

        for yMap in Int(handRect.minY) ..< Int(handRect.maxY) {
            let rowData = CVPixelBufferGetBaseAddress(depthPixelBuffer)! + yMap * CVPixelBufferGetBytesPerRow(depthPixelBuffer)
            let rowIndex = yMap * depthWidth
            let classRowIndex = (yMap - Int(handRect.minY)) * Int(handRect.width) * 4
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            for index in Int(handRect.minX) ..< Int(handRect.maxX) {
                if data[index] > 0 && data[index] <= cutOff {
                    let value = UInt8(max(data[index] - minDepth, 0) / 0.16 * 255)
                    grayImage[rowIndex + index] = value
                    classImage[classRowIndex + (index - Int(handRect.minX)) * 4] = value
                    classImage[classRowIndex + (index - Int(handRect.minX)) * 4 + 1] = value
                    classImage[classRowIndex + (index - Int(handRect.minX)) * 4 + 2] = value
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        let classColorspace = CGColorSpaceCreateDeviceRGB()

        let classContext = CGContext(data: nil,
                                width: Int(handRect.width),
                                height: Int(handRect.height),
                                bitsPerComponent: 8,
                                bytesPerRow: Int(handRect.width) * 4,
                                space: classColorspace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        classContext.data?.copyMemory(from: classImage, byteCount: classImage.count)

        let classCGImage = classContext.makeImage()!

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: classCGImage, orientation: self.exifOrientationFromDeviceOrientation())
            do {
                try handler.perform([self.visionRequest])
            } catch {
                /*
                 This handler catches general image processing errors. The `classificationRequest`'s
                 completion handler `processClassifications(_:error:)` catches errors specific
                 to processing that request.
                 */
                print("Failed to perform classification.\n\(error.localizedDescription)")
            }
        }

        let colorspace = CGColorSpaceCreateDeviceGray()

        let context = CGContext(data: nil,
                                width: depthWidth,
                                height: depthHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: depthWidth,
                                space: colorspace,
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.data?.copyMemory(from: grayImage, byteCount: depthHeight * depthWidth)

        let cgImage = context.makeImage()!
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .left)
        let handRectRotated = CGRect(x: handRect.minY, y: CGFloat(depthWidth) - handRect.maxX, width: handRect.height, height: handRect.width)
        DispatchQueue.main.async {
            self.imageView.image = image
            self.handRect.frame = self.imageView.convertRect(fromImageRect: handRectRotated)
        }
    }

    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
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
