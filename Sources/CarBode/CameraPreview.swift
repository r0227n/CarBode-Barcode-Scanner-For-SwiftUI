//
//  CameraPreview.swift
//  
//
//  Created by narongrit kanhanoi on 7/10/2562 BE.
//  Copyright © 2562 PAM. All rights reserved.
//

import UIKit
import AVFoundation

public class CameraPreview: UIView {

    var cameraInput: AVCaptureDeviceInput?
    var cameraPosition = AVCaptureDevice.Position.back
    var previewLayer: AVCaptureVideoPreviewLayer?
    var session: AVCaptureSession?
    var supportBarcode: [AVMetadataObject.ObjectType]?

    private var label: UILabel?

    var scanInterval: Double = 3.0
    var lastTime = Date(timeIntervalSince1970: 0)

    var onFound: OnFound?
    var mockBarCode: BarcodeData?
    var selectedCamera: AVCaptureDevice?
    
    var torchLightIsOn:Bool = false

    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupScanner() {
        #if targetEnvironment(simulator)
            createSimulatorView()
        #else
            checkCameraAuthorizationStatus()
        #endif
    }

    func setSupportedBarcode(supportBarcode: [AVMetadataObject.ObjectType]){
        self.supportBarcode = supportBarcode
        
        guard let session = session else {return}
        
        session.beginConfiguration()
        
        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)

            metadataOutput.metadataObjectTypes = supportBarcode
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        }
        
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)

            metadataOutput.metadataObjectTypes = supportBarcode
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        }
        session.commitConfiguration()
    }
    
    func setCamera(position: AVCaptureDevice.Position) {
        
        if cameraPosition == position {return}
        cameraPosition = position
        
        guard let session = session else {return}
        
        session.beginConfiguration()
        if let input = cameraInput {
            session.removeInput(input)
            cameraInput = nil
        }

        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: cameraPosition)
        
        let camera = deviceDiscoverySession.devices.first
        if let selectedCamera = camera {
            if let input = try? AVCaptureDeviceInput(device: selectedCamera) {
                if session.canAddInput(input) {
                    session.addInput(input)
                    cameraInput = input
                }
            }
        }

        session.commitConfiguration()
    }

    func setTorchLight(isOn: Bool) {
        
        if torchLightIsOn == isOn {return}
        
        torchLightIsOn = isOn
        if let camera = selectedCamera {
            if camera.hasTorch {
                try? camera.lockForConfiguration()
                if isOn {
                    camera.torchMode = .on
                } else {
                    camera.torchMode = .off
                }
                camera.unlockForConfiguration()
            }
        }
    }

    private func checkCameraAuthorizationStatus() {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorizationStatus == .authorized {
            setupCamera()
        } else {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.sync {
                    if granted {
                        self.setupCamera()
                    }
                }
            }
        }
    }

    func setupCamera() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: cameraPosition)

        if let selectedCamera = deviceDiscoverySession.devices.first {
            if let input = try? AVCaptureDeviceInput(device: selectedCamera) {

                let session = AVCaptureSession()
                session.sessionPreset = .photo

                if session.canAddInput(input) {
                    session.addInput(input)
                    cameraInput = input
                }

                let metadataOutput = AVCaptureMetadataOutput()

                if session.canAddOutput(metadataOutput) {
                    session.addOutput(metadataOutput)

                    metadataOutput.metadataObjectTypes = supportBarcode
                    metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                }

                previewLayer?.removeFromSuperlayer()
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)

                self.backgroundColor = UIColor.gray
                previewLayer.videoGravity = .resizeAspectFill
                self.layer.addSublayer(previewLayer)
                self.previewLayer = previewLayer

                session.startRunning()

                self.session = session
                self.previewLayer = previewLayer
                self.selectedCamera = selectedCamera
                
            }
        }
    }


    func getVideoOrientation() -> AVCaptureVideoOrientation {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene, windowScene.activationState == .foregroundActive
            else { return .portrait }

        let interfaceOrientation = windowScene.interfaceOrientation

        switch interfaceOrientation {
        case .unknown:
            return .portrait
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        @unknown default:
            return .portrait
        }
    }

    func updateCameraView() {
        previewLayer?.connection?.videoOrientation = getVideoOrientation()
    }

    func createSimulatorView() {
        self.backgroundColor = UIColor.black
        label = UILabel(frame: self.bounds)
        label?.numberOfLines = 4
        label?.text = "CarBode Scanner View\nSimulator mode\n\nClick here to simulate scan"
        label?.textColor = UIColor.white
        label?.textAlignment = .center
        if let label = label {
            addSubview(label)
        }
        let gesture = UITapGestureRecognizer(target: self, action: #selector(onClick))
        self.addGestureRecognizer(gesture)
    }

    @objc func onClick() {
        foundBarcode(mockBarCode ?? BarcodeData(value: "Mock Value", type: .qr))
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        #if targetEnvironment(simulator)
            label?.frame = self.bounds
        #else
            previewLayer?.frame = self.bounds
        #endif
    }
}

extension CameraPreview: AVCaptureMetadataOutputObjectsDelegate {

    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            if let stringValue = readableObject.stringValue {
                let barcode = BarcodeData(value: stringValue, type: readableObject.type)
                foundBarcode(barcode)
            }
        }
    }

    func foundBarcode(_ barcode: BarcodeData) {
        let now = Date()
        if now.timeIntervalSince(lastTime) >= scanInterval {
            lastTime = now
            
            if let onFound = onFound {
                onFound(barcode)
            }
        }
    }
}
