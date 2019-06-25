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
import VideoToolbox

class RecognitionViewController: UIViewController, CaptureSessionDelegate {

    private var session: CaptureSession?

    private let handTracker = HandTracker()
    private let stabilizationDetector = StabilizationDetector()
    private let classifier = GestureClassifier()
    private let wordComposer = WordComposer()

    private var depthCutOff: Float = 0.15

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var classificationLabel: UILabel!
    @IBOutlet weak var resultView: UIView!
    @IBOutlet weak var resultTextView: UITextView!

    let handRect = UIView()
    let previewView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()

        stabilizationDetector.delegate = self
        classifier.delegate = self

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
        resultView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        resultView.layer.cornerRadius = 4
    }

    func setupViews() {
//        view.addSubview(previewView)

        resultTextView.inputView = UIView()

        handRect.backgroundColor = .clear
        handRect.layer.borderColor = UIColor.green.cgColor
        handRect.layer.borderWidth = 4
        imageView.addSubview(handRect)
    }

    func setupSession() {
        session = CaptureSession()
        session?.delegate = self
        //previewView.layer.addSublayer(session.previewLayer)
        session?.startSession()
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        handTracker.automatic = Settings.autodetectHand
        session?.startSession()
        UIApplication.shared.isIdleTimerDisabled = true
        becomeFirstResponder()
        resultTextView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        session?.stopSession()
        super.viewWillDisappear(animated)
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            wordComposer.removeLastLetter()
            resultTextView.attributedText = currentAttributedString()
        }
    }

    func didOutputSynchronizedData(syncedDepthData: AVCaptureSynchronizedDepthData, syncedVideoData: AVCaptureSynchronizedSampleBufferData) {

        let depthPixelBuffer = syncedDepthData.depthData.depthDataMap
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(syncedVideoData.sampleBuffer) else {
            return
        }

        guard stabilizationDetector.sceneStabilityAchieved(newFrame: videoPixelBuffer) else {
            var cgImage: CGImage?
            VTCreateCGImageFromCVPixelBuffer(videoPixelBuffer, options: nil, imageOut: &cgImage)

            if let cgImage = cgImage {
                let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
                DispatchQueue.main.async {
                    self.wordComposer.clearClassifications()
                    self.imageView.image = image
                    self.handRect.isHidden = true
                }
            }
            return
        }

        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)

        CVPixelBufferLockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        var (handRect, minDepth) = handTracker.handRect(in: depthPixelBuffer, depthCutOff: depthCutOff)
        let cutOff = minDepth + depthCutOff
        
        var grayImage = [UInt8](repeating: 0, count: depthWidth * depthHeight)
        var classImage = [UInt8](repeating: 0, count: Int(handRect.width * handRect.height))

        for yMap in Int(handRect.minY) ..< Int(handRect.maxY) {
            let rowData = CVPixelBufferGetBaseAddress(depthPixelBuffer)! + yMap * CVPixelBufferGetBytesPerRow(depthPixelBuffer)
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

        if let classContext = CGContext(data: nil,
                                           width: Int(handRect.width),
                                           height: Int(handRect.height),
                                           bitsPerComponent: 8,
                                           bytesPerRow: Int(handRect.width),
                                           space: classColorspace,
                                           bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            classContext.data?.copyMemory(from: classImage, byteCount: classImage.count)
            let classCGImage = classContext.makeImage()!
            self.classifier.recognize(image: classCGImage)
        }

        let colorspace = CGColorSpaceCreateDeviceGray()

        var cgImage: CGImage?
        if Settings.debugMode {
            let context = CGContext(data: nil,
                                    width: depthWidth,
                                    height: depthHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: depthWidth,
                                    space: colorspace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.data?.copyMemory(from: grayImage, byteCount: depthHeight * depthWidth)
            cgImage = context.makeImage()!
        } else {
            VTCreateCGImageFromCVPixelBuffer(videoPixelBuffer, options: nil, imageOut: &cgImage)
        }
        
        if let cgImage = cgImage {
            let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            handRect.origin.x *= image.size.width / CGFloat(depthWidth)
            handRect.origin.y *= image.size.height / CGFloat(depthHeight)
            handRect.size.height *= image.size.height / CGFloat(depthHeight)
            handRect.size.width *= image.size.width / CGFloat(depthWidth)
            DispatchQueue.main.async {
                self.imageView.image = image
                self.handRect.isHidden = false
                self.handRect.frame = self.imageView.convertRect(fromImageRect: handRect)
            }
        }
    }
}

extension RecognitionViewController: StabilizationDetectorDelegate {
    func sceneStabilityAchieved(at frame: CVPixelBuffer) {

    }

    func sceneStabilityNotAchieved() {
    }
}

extension RecognitionViewController: GestureClassifierDelegate {
    func recognized(results: [String: Float]) {
        DispatchQueue.main.async {
            self.wordComposer.add(classifications: results)
            let topClassifications = results.map { ($0.key, $0.value) }.sorted(by: { return $0.1 > $1.1 }).prefix(2)
            let descriptions = topClassifications.map { (identifier, confidence) in
                return String(format: "  (%.2f) %@", confidence, identifier)
            }
            self.classificationLabel.text = descriptions.joined(separator: "\n")
            self.resultTextView.attributedText = self.currentAttributedString()
        }
    }

    func currentAttributedString() -> NSAttributedString {
        let attrString = NSMutableAttributedString(string: wordComposer.currentText.uppercased(),
                                                   attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold)])
        if let currentLetter = wordComposer.currentLetter {
            let currentLetterColor: UIColor
            switch currentLetter.confidence {
            case .low:
                currentLetterColor = UIColor(red: 0.9, green: 0, blue: 0, alpha: 1)
            case .medium:
                currentLetterColor = UIColor(red: 0.7, green: 0.5, blue: 0.1, alpha: 1)
            case .high:
                currentLetterColor = UIColor(red: 0.0, green: 0.5, blue: 0, alpha: 1)
            }
            attrString.append(NSAttributedString(string: currentLetter.letter.uppercased(),
                                                 attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold),
                                                              .foregroundColor: currentLetterColor]))
        }
        return attrString
    }
}
