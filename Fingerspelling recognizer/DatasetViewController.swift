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

class DatasetViewController: UIViewController, CaptureSessionDelegate {

    private let labels = ["1", "2", "3", "4", "5", "6", "7", "8", "9",
                          "a", "b", "c", "d", "e", "f", "g", "h", "i",
                          "k", "l", "m", "n", "o", "p", "q", "r", "s",
                          "t", "u", "x", "y"]
    private let imagesPerLabel = 200
    private var currentLabelIndex = 0
    private var currentImageIndex = 0
    private var capturingEnabled = false
    private let handTracker: HandTracker = {
        let handTracker = HandTracker()
        handTracker.automatic = false
        return handTracker
    }()

    private var session: CaptureSession!

    private var depthCutOff: Float = 0.15

    private let imageView = UIImageView()
    private var frame = 1

    let labelLabel = UILabel()
    let handRect = UIView()
    let captureButton = UIButton(type: .system)
    let stepper = UIStepper()
    var signerId: Int = 1
    let signerIdLabel = UILabel()
    let signerIdStepper = UIStepper()
    let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

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

        view.addSubview(imageView)
        labelLabel.font = UIFont.systemFont(ofSize: 24)
        labelLabel.textColor = .red
        labelLabel.textAlignment = .center
        view.addSubview(labelLabel)
        labelLabel.text = labels[0]

        signerIdLabel.font = UIFont.systemFont(ofSize: 24)
        signerIdLabel.textColor = .red
        signerIdLabel.textAlignment = .center
        view.addSubview(signerIdLabel)
        signerIdLabel.text = "Signer: \(signerId)"

        captureButton.tintColor = UIColor.blue
        captureButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        captureButton.setTitle("Start", for: .normal)
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        stepper.minimumValue = 0
        stepper.maximumValue = Double(labels.count - 1)
        stepper.wraps = true
        stepper.stepValue = 1
        stepper.value = 0
        stepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
        view.addSubview(stepper)

        signerIdStepper.minimumValue = 1
        signerIdStepper.maximumValue = 100
        signerIdStepper.wraps = true
        signerIdStepper.stepValue = 1
        signerIdStepper.value = 0
        signerIdStepper.addTarget(self, action: #selector(signerStepperChanged), for: .valueChanged)
        view.addSubview(signerIdStepper)

        handRect.backgroundColor = .clear
        handRect.layer.borderColor = UIColor.green.cgColor
        handRect.layer.borderWidth = 4
        imageView.addSubview(handRect)
        
        doneButton.setTitle("Done", for: .normal)
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        doneButton.tintColor = .red
        view.addSubview(doneButton)
    }
    
    @objc
    func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func captureButtonTapped() {
        capturingEnabled.toggle()
        if !capturingEnabled {
            currentImageIndex = 0
        }
        updateCaptureButton()
    }

    @objc
    func stepperChanged() {
        currentLabelIndex = Int(stepper.value)
        labelLabel.text = "Label: \(labels[currentLabelIndex])"
    }

    @objc
    func signerStepperChanged() {
        signerId = Int(signerIdStepper.value)
        signerIdLabel.text = "Signer: \(signerId)"
    }

    func updateCaptureButton() {
        if capturingEnabled {
            captureButton.setTitle("Stop", for: .normal)
        } else {
            captureButton.setTitle("Start", for: .normal)
        }
    }

    func setupSession() {
        session = CaptureSession()
        session.delegate = self
        session.startSession()
    }

    override func viewDidLayoutSubviews() {
        imageView.frame = view.bounds.inset(by: view.safeAreaInsets)
        captureButton.frame = CGRect(x: 140, y: view.bounds.height - 80, width: 100, height: 50)
        labelLabel.frame = CGRect(x: 20, y: view.bounds.height - 130, width: 100, height: 50)
        stepper.frame = CGRect(x: 20, y: view.bounds.height - 80, width: 60, height: 50)
        signerIdLabel.frame = CGRect(x: view.bounds.width - 100, y: view.bounds.height - 130, width: 100, height: 50)
        signerIdStepper.frame = CGRect(x: view.bounds.width - 100, y: view.bounds.height - 80, width: 60, height: 50)
        doneButton.frame = CGRect(x: view.bounds.width - 128, y: 20, width: 100, height: 40)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        session.stopSession()
        super.viewWillDisappear(animated)
    }

    func didOutputSynchronizedData(syncedDepthData: AVCaptureSynchronizedDepthData, syncedVideoData: AVCaptureSynchronizedSampleBufferData) {

        let depthPixelBuffer = syncedDepthData.depthData.depthDataMap

        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)

        CVPixelBufferLockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)

        let (handRect, minDepth) = handTracker.handRect(in: depthPixelBuffer, depthCutOff: depthCutOff)
        let cutOff = minDepth + depthCutOff

        var grayImage = [UInt8](repeating: 0, count: depthWidth * depthHeight)
        var classImage = [UInt8](repeating: 0, count: Int(handRect.width * handRect.height))

        for yMap in Int(handRect.minY) ..< Int(handRect.maxY) {
            let rowData = baseAddress + yMap * bytesPerRow
            let rowIndex = yMap * depthWidth
            let classRowIndex = (yMap - Int(handRect.minY)) * Int(handRect.width)
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            for index in Int(handRect.minX) ..< Int(handRect.maxX) {
                if data[index] > 0 && data[index] <= cutOff {
                    let value = UInt8(max(data[index] - minDepth, 0) / 0.15 * 255)
                    grayImage[rowIndex + index] = value
                    classImage[classRowIndex + (index - Int(handRect.minX))] = value
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        let classColorspace = CGColorSpaceCreateDeviceGray()

        let classContext = CGContext(data: nil,
                                width: Int(handRect.width),
                                height: Int(handRect.height),
                                bitsPerComponent: 8,
                                bytesPerRow: Int(handRect.width),
                                space: classColorspace,
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        classContext.data?.copyMemory(from: classImage, byteCount: classImage.count)

        let classCGImage = classContext.makeImage()!
        frame += 1
        if frame % 4 == 0 && capturingEnabled {
            frame = 1
            currentImageIndex += 1
            let classUIImage = UIImage(cgImage: classCGImage, scale: 1, orientation: .up)
            let label = labels[currentLabelIndex]
            let fileName = "s\(signerId)_\(label)_\(currentImageIndex).jpeg"
            let path = folder(for: label) + "/" + fileName
            try! classUIImage.jpegData(compressionQuality: 0.9)?.write(to: URL(fileURLWithPath: path))
            if currentImageIndex == imagesPerLabel {
                currentLabelIndex = (currentLabelIndex + 1) % labels.count
                currentImageIndex = 0
                capturingEnabled = false
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
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        DispatchQueue.main.async {
            self.imageView.image = image
            self.handRect.frame = self.imageView.convertRect(fromImageRect: handRect)
            self.labelLabel.text = "Label: \(self.labels[self.currentLabelIndex])"
            self.stepper.value = Double(self.currentLabelIndex)
            self.updateCaptureButton()
        }
    }

    public func folder(for label: String) -> String {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let folder = docs + "/fingerspelling/\(label)/"
        if !FileManager.default.fileExists(atPath: folder) {
            try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: nil)
        }
        return folder
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
