//
//  CaptureSession.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 08/04/2019.
//  Copyright © 2019 aa. All rights reserved.
//

import Foundation
import AVFoundation

protocol CaptureSessionDelegate: class {
    func didOutputSynchronizedData(syncedDepthData: AVCaptureSynchronizedDepthData, syncedVideoData: AVCaptureSynchronizedSampleBufferData)
}

class CaptureSession: NSObject {

    private let session = AVCaptureSession()
    private var captureDevice: AVCaptureDevice
    private var videoDeviceInput: AVCaptureDeviceInput
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let dataOutputQueue = DispatchQueue(label: "fingerspelling.videoOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    private let outputSynchronizer: AVCaptureDataOutputSynchronizer

    weak var delegate: CaptureSessionDelegate?
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        return previewLayer
    }()

    override init() {
        captureDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                         mediaType: .video,
                                                         position: .front).devices.first!
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            captureDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            captureDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
        }
        videoDeviceInput = try! AVCaptureDeviceInput(device: captureDevice)
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.hd1280x720
        session.addInput(videoDeviceInput)
        session.addOutput(videoDataOutput)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        depthDataOutput.isFilteringEnabled = false
        session.addOutput(depthDataOutput)
        // Search for highest resolution with floating-point depth values
        let depthFormats = captureDevice.activeFormat.supportedDepthDataFormats
        let depth32formats = depthFormats.filter({
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
        })
        let selectedFormat = depth32formats.max(by: { first, second in
            CMVideoFormatDescriptionGetDimensions(first.formatDescription).width <
                CMVideoFormatDescriptionGetDimensions(second.formatDescription).width })

        do {
            try captureDevice.lockForConfiguration()
            captureDevice.activeDepthDataFormat = selectedFormat
            captureDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
        }
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        super.init()
        outputSynchronizer.setDelegate(self, queue: dataOutputQueue)
        session.commitConfiguration()
    }

    func startSession() {
        session.startRunning()
        let depthConnection = depthDataOutput.connection(with: .depthData)!
        depthConnection.videoOrientation = .portrait
        depthConnection.automaticallyAdjustsVideoMirroring = false
        depthConnection.isVideoMirrored = true
        let videoOutputConnection = videoDataOutput.connection(with: .video)!
        videoOutputConnection.videoOrientation = .portrait
        videoOutputConnection.isVideoMirrored = true
    }

    func stopSession() {
        session.stopRunning()
    }
}

extension CaptureSession: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {

        // Read all outputs
        guard let syncedDepthData: AVCaptureSynchronizedDepthData =
            synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
            let syncedVideoData: AVCaptureSynchronizedSampleBufferData =
            synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else {
                // only work on synced pairs
                return
        }

        if syncedDepthData.depthDataWasDropped || syncedVideoData.sampleBufferWasDropped {
            return
        }

        delegate?.didOutputSynchronizedData(syncedDepthData: syncedDepthData, syncedVideoData: syncedVideoData)
    }
}
