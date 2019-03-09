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

class ViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate {

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    private var setupResult: SessionSetupResult = .success

    private let session = AVCaptureSession()

    private var isSessionRunning = false

    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], autoreleaseFrequency: .workItem)

    private var captureDevice: AVCaptureDevice!

    private var videoDeviceInput: AVCaptureDeviceInput!

    private let dataOutputQueue = DispatchQueue(label: "video data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)

    private let videoDataOutput = AVCaptureVideoDataOutput()

    private let depthDataOutput = AVCaptureDepthDataOutput()

    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?

    private var renderingEnabled = true

    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                                               mediaType: .video,
                                                                               position: .front)

    private var statusBarOrientation: UIInterfaceOrientation = .portrait

    private var depthCutOff: Float = 0.16

    private let imageView = UIImageView()
    private let slider = UISlider()
    private var frame = 3

    private let cutOffLabel = UILabel()
    let handRect = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break

        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             We suspend the session queue to delay session setup until the access request has completed
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })

        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }

        view.addSubview(imageView)
        slider.minimumValue = 0.05
        slider.maximumValue = 0.5
        slider.value = depthCutOff
        slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        view.addSubview(slider)
        cutOffLabel.font = UIFont.systemFont(ofSize: 24)
        cutOffLabel.textColor = .red
        cutOffLabel.textAlignment = .center
        view.addSubview(cutOffLabel)

        handRect.backgroundColor = .clear
        handRect.layer.borderColor = UIColor.green.cgColor
        handRect.layer.borderWidth = 4
        imageView.addSubview(handRect)

        let tapGR = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        view.addGestureRecognizer(tapGR)

        sessionQueue.async {
            self.configureSession()
        }
    }

    var tapPoint: CGPoint?

    @objc func tapped(_ gr: UITapGestureRecognizer) {
        tapPoint = imageView.convertPoint(fromViewPoint: gr.location(in: view))
    }

    @objc func valueChanged() {
        dataOutputQueue.async {
            self.depthCutOff = self.slider.value
            DispatchQueue.main.async {
                self.cutOffLabel.text = "\(self.depthCutOff)"
            }
        }
    }

    override func viewDidLayoutSubviews() {
        imageView.frame = view.bounds.inset(by: view.safeAreaInsets)
        slider.frame = CGRect(x: 40, y: view.bounds.height - 70, width: view.bounds.width - 80, height: 50)
        cutOffLabel.frame = CGRect(x: 40, y: view.bounds.height - 140, width: view.bounds.width - 80, height: 50)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        statusBarOrientation = interfaceOrientation

        UIApplication.shared.isIdleTimerDisabled = true

        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded
                self.addObservers()
                self.dataOutputQueue.async {
                    self.renderingEnabled = true
                }

                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning

            case .notAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("TrueDepthBackdrop doesn't have permission to use the camera, please change privacy settings",
                                                    comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "TrueDepthBackdrop", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))

                    self.present(alertController, animated: true, completion: nil)
                }
            case .configurationFailed:
                break
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        dataOutputQueue.async {
            self.renderingEnabled = false
        }
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }

        super.viewWillDisappear(animated)
    }

    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources
        dataOutputQueue.async {
            self.renderingEnabled = false
        }
    }

    @objc
    func willEnterForground(notification: NSNotification) {
        dataOutputQueue.async {
            self.renderingEnabled = true
        }
    }

    // MARK: - KVO and Notifications

    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)

        captureDevice.addObserver(self, forKeyPath: "systemPressureState", options: NSKeyValueObservingOptions.new, context: nil)

        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted),
                                               name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded),
                                               name: NSNotification.Name.AVCaptureSessionInterruptionEnded,
                                               object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        captureDevice.removeObserver(self, forKeyPath: "systemPressureState", context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "systemPressureState" {

            let level = captureDevice.systemPressureState.level

            var recommendedFrameRate: Int32
            switch level {
            case .nominal, .fair:
                recommendedFrameRate = 30
            case .serious, .critical:
                recommendedFrameRate = 15
            case .shutdown:
                // no need to do anything. iOS is going to shut us down anyway...
                return
            default:
                assertionFailure("unknown system pressure level")
                return
            }

            print("System pressure state is now \(level.rawValue). Will set frame rate to \(recommendedFrameRate)")

            do {
                try captureDevice.lockForConfiguration()
                captureDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: recommendedFrameRate)
                captureDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: recommendedFrameRate)
                captureDevice.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - Session Management

    // Call this on the session queue
    private func configureSession() {
        if setupResult != .success {
            return
        }

        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first

        guard let videoDevice = defaultVideoDevice else {
            print("Could not find any video device")
            setupResult = .configurationFailed
            return
        }

        captureDevice = videoDevice

        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }

        session.beginConfiguration()

        session.sessionPreset = AVCaptureSession.Preset.hd1280x720

        // Add a video input
        guard session.canAddInput(videoDeviceInput) else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)

        // Add a video data output
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Add a depth data output
        if session.canAddOutput(depthDataOutput) {
            session.addOutput(depthDataOutput)
            depthDataOutput.isFilteringEnabled = true
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
            } else {
                print("No AVCaptureConnection")
            }
        } else {
            print("Could not add depth data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Search for highest resolution with floating-point depth values
        let depthFormats = videoDevice.activeFormat.supportedDepthDataFormats
        let depth32formats = depthFormats.filter({
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
        })
        if depth32formats.isEmpty {
            print("Device does not support Float32 depth format")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        let selectedFormat = depth32formats.max(by: { first, second in
            CMVideoFormatDescriptionGetDimensions(first.formatDescription).width <
                CMVideoFormatDescriptionGetDimensions(second.formatDescription).width })

        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeDepthDataFormat = selectedFormat
            videoDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer!.setDelegate(self, queue: dataOutputQueue)
        session.commitConfiguration()
    }

    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
        }
    }

    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
    }

    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }

        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")

        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }

    // MARK: - Video + Depth Output Synchronizer Delegate

    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {

        // Read all outputs
        guard renderingEnabled,
            let syncedDepthData: AVCaptureSynchronizedDepthData =
            synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
            let syncedVideoData: AVCaptureSynchronizedSampleBufferData =
            synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else {
                // only work on synced pairs
                return
        }

        if syncedDepthData.depthDataWasDropped || syncedVideoData.sampleBufferWasDropped {
            return
        }

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

        var handRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: 0, dy: -10)
        if handRect.width/handRect.height > 1.5 {
            handRect.size.width = 1.5 * handRect.height
        }

        var grayImage = [UInt8](repeating: 0, count: depthWidth * depthHeight)

        for yMap in minY ..< maxY {
            let rowData = CVPixelBufferGetBaseAddress(depthPixelBuffer)! + yMap * CVPixelBufferGetBytesPerRow(depthPixelBuffer)
            let rowIndex = yMap * depthWidth
            let data = UnsafeMutableBufferPointer<Float32>(start: rowData.assumingMemoryBound(to: Float32.self), count: depthWidth)
            for index in minX ..< maxX {
                if data[index] > 0 && data[index] <= cutOff {
                    grayImage[rowIndex + index] = UInt8((1 - min(data[index], 1)) * 255)
                } else {
                    grayImage[rowIndex + index] = 0
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

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
}
