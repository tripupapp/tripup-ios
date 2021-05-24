//
//  CameraView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 31/05/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation

import AVFoundation
import UIKit

class CameraView: UIViewController {
    private enum Orientation {
        case portrait
        case portraitUpsideDown
        case landscapeLeft
        case landscapeRight

        static var current: Orientation {
            switch (UIDevice.current.orientation) {
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            default:
                return .portrait
            }
        }

        var isPortraitVariety: Bool {
            return (self == .portrait || self == .portraitUpsideDown) ? true : false
        }

        var AVOrientation: AVCaptureVideoOrientation {
            switch self {
            case .portrait:
                return .portrait
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .landscapeLeft:
                return .landscapeRight
            case .landscapeRight:
                return .landscapeLeft
            }
        }

        var CGTransform: CGAffineTransform {
            switch self {
            case .portrait:
                return CGAffineTransform(rotationAngle: 0)
            case .landscapeLeft:
                return CGAffineTransform(rotationAngle: .pi / 2)
            case .portraitUpsideDown:
                return CGAffineTransform(rotationAngle: .pi)
            case .landscapeRight:
                return CGAffineTransform(rotationAngle: .pi * 1.5)
            }
        }
    }

    @IBOutlet var mainView: UIView!
    @IBOutlet var shutterWidthPortrait: NSLayoutConstraint!
    @IBOutlet var shutterWidthLandscape: NSLayoutConstraint!
    @IBOutlet var flipCamera: UIButton!
    @IBOutlet var zoomLabel: UILabel!
    @IBOutlet var flashButton: UIButton!
    @IBOutlet var focusSquare: UIImageView!
    @IBOutlet var focusSquareWidth: NSLayoutConstraint!
    @IBOutlet var focusSquareCenterX: NSLayoutConstraint!
    @IBOutlet var focusSquareCenterY: NSLayoutConstraint!
    @IBOutlet var thumbnail: UIImageView!

    private lazy var blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .dark)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.frame = self.mainView.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return blurView
    }()

    private lazy var flashIconOn: UIImage = {
        return UIImage(named: "ios-flash")!
    }()
    private lazy var flashIconOff: UIImage = {
        return UIImage(named: "ios-flash-off")!
    }()

    private let log = Logger.self

    private let backCameraInput: AVCaptureDeviceInput? = {
        return CameraView.bestCaptureInput(for: .back)
    }()
    private let frontCameraInput: AVCaptureDeviceInput? = {
        return CameraView.bestCaptureInput(for: .front)
    }()

    private static func bestCaptureInput(for position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let captureDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) ??
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return nil }

        try! captureDevice.lockForConfiguration()
        if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
            captureDevice.focusMode = .continuousAutoFocus
        }
        captureDevice.isSubjectAreaChangeMonitoringEnabled = true
        captureDevice.unlockForConfiguration()

        return try? AVCaptureDeviceInput(device: captureDevice)
    }

    private var captureSession: AVCaptureSession?
    private let captureSessionQueue = DispatchQueue(label: "app.tripup.cameraview.capturesessionqueue", qos: .userInitiated)
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var capturePhotoOutput: AVCapturePhotoOutput?

    private var ownerID: UUID!
//    private var imageManager: ImageManager!
//    private var tripObserverRegister: TripObserverRegister?

//    private var trip: Trip!
    private var portraitMode = Orientation.current.isPortraitVariety
    private var frontCameraActive = false
    private let cameraConfigQueue = DispatchQueue(label: "app.tripup.cameraview.cameraconfigqueue", qos: .userInitiated)
    private var startZoomFactor: CGFloat = 1.0
    private var flashMode = AVCaptureDevice.FlashMode.off
    private var systemAdjustingFocusObserver: NSKeyValueObservation?
    private var originalBarTintColor: UIColor? = .black
    private var originalBarBackgroundColor: UIColor? = .white

    private var flipAnimator: UIViewPropertyAnimator?
    private var zoomAlphaAnimator: UIViewPropertyAnimator?

    private let captureObjectsInProgress = AtomicVar<Set<PhotoCaptureObject>>(Set<PhotoCaptureObject>())
    private let locationManager = LocationManager()

    func initialise(ownerID: UUID/*, imageManager: ImageManager, trip: Trip, tripObserverRegister: TripObserverRegister?*/) {
        self.ownerID = ownerID
//        imageManager = args.imageManager
//        trip = args.trip
//        tripObserverRegister = args.tripObserverRegister
    }

    func assertDependencies() {
        assert(ownerID != nil)
//        assert(imageManager != nil)
//        assert(trip != nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        assertDependencies()

        if let captureInput = backCameraInput {
            let capturePhotoOutput = AVCapturePhotoOutput()
            capturePhotoOutput.isHighResolutionCaptureEnabled = true

            let captureSession = AVCaptureSession()
            guard captureSession.canAddInput(captureInput) else { log.error("can't add input"); return }
            guard captureSession.canAddOutput(capturePhotoOutput) else { log.error("can't add output"); return }

            captureSession.beginConfiguration()
            captureSession.sessionPreset = .photo
            captureSession.addInput(captureInput)
            captureSession.addOutput(capturePhotoOutput)
            captureSession.commitConfiguration()

            // configure view to display camera feed
            let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer.videoGravity = .resizeAspect
            videoPreviewLayer.frame = mainView.layer.bounds
            mainView.layer.addSublayer(videoPreviewLayer)

            self.captureSession = captureSession
            self.videoPreviewLayer = videoPreviewLayer
            self.capturePhotoOutput = capturePhotoOutput

            systemAdjustingFocusObserver = captureInput.observe(\.device.isAdjustingFocus, options: [.old, .new]) { [unowned self] (_, change) in
                guard let oldValue = change.oldValue, let newValue = change.newValue else { return }
                guard oldValue == false, newValue == true else { return }

                let oldConstraint = self.focusSquareWidth!
                let newConstraint = NSLayoutConstraint(item: oldConstraint.firstItem!, attribute: oldConstraint.firstAttribute, relatedBy: oldConstraint.relation, toItem: oldConstraint.secondItem, attribute: oldConstraint.secondAttribute, multiplier: oldConstraint.multiplier * 2, constant: oldConstraint.constant)

                self.view.removeConstraint(oldConstraint)
                self.view.addConstraint(newConstraint)
                self.view.layoutIfNeeded()
                self.focusSquare.alpha = 1.0

                let animator = UIViewPropertyAnimator(duration: 0.3, curve: .easeIn) {
                    self.view.removeConstraint(newConstraint)
                    self.view.addConstraint(oldConstraint)
                    self.view.layoutIfNeeded()
                }
                animator.addCompletion { position in
                    guard position == .end else { return }
                    UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0, options: UIView.AnimationOptions.curveEaseOut, animations: {
                        self.focusSquare.alpha = 0
                    }, completion: nil)
                }
                animator.startAnimation()
            }
        }

        thumbnail.layer.borderWidth = 2
        thumbnail.layer.borderColor = UIColor.white.cgColor
        thumbnail.layer.cornerRadius = 5.0
        thumbnail.layer.masksToBounds = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        NotificationCenter.default.addObserver(self, selector: #selector(recalibrateCamera), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetFocusPoint), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: nil)

        if let captureSession = captureSession {
            startAndRemoveBlur(for: captureSession)
        }
//        if let asset = trip.album.lastAsset {
//            imageManager.requestImage(for: asset, delivery: .fast) { image, _ in
//                self.thumbnail.image = image
//            }
//        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        recalibrateCamera() // when returning to this view from a modally presented view (eg. photos view), recalibrate camera if rotation changed whilst in the other view
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: nil)

        if let captureSession = captureSession {
            addBlurAndStop(session: captureSession)
        }
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        // willMove is called twice, once when CameraView is loaded (before viewDidLoad) and again when unloaded. When loaded, parent == RootView, when unloaded parent is something else (not sure what...)
        // Anyway, just test if parent is RootView. If NOT, it means we're unloading, so reset nav bar (which must be done here as there is a delay otherwise when resetting colour... see comment below)
        // (For consistency, we therefore save the original nav bar colours here too instead of viewWillAppear. Because willMove is only called on first and last load of camera view, not when something is presented modally over it.
        // In other words, save the colours on first load, restore colours on unload)
        if let _ = parent as? RootView {
            originalBarTintColor = self.navigationController?.navigationBar.tintColor
            originalBarBackgroundColor = self.navigationController?.navigationBar.barTintColor
            self.navigationController?.navigationBar.barTintColor = .black
            self.navigationController?.navigationBar.tintColor = .white
        } else {
            self.navigationController?.navigationBar.barTintColor = originalBarBackgroundColor  // placing this in viewWillDisappear causes delay for some reason... https://stackoverflow.com/a/49143465/2728986
            self.navigationController?.navigationBar.tintColor = originalBarTintColor
        }
    }

    private func startAndRemoveBlur(for captureSession: AVCaptureSession) {
        self.captureSessionQueue.async {
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
            DispatchQueue.main.async {
                self.blurView.removeFromSuperview()
            }
        }
    }

    private func addBlurAndStop(session captureSession: AVCaptureSession) {
        mainView.addSubview(blurView)
        self.captureSessionQueue.async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    @objc private func recalibrateCamera() {
        // the order of events is important for the animations. Caution when changing...
        guard Orientation.current.isPortraitVariety != portraitMode else { log.debug("already in portrait mode. No need to recalibrate camera or view"); return }
        guard let captureSession = self.captureSession, let videoPreviewLayer = self.videoPreviewLayer else { return }

        addBlurAndStop(session: captureSession)
        portraitMode = !portraitMode
        videoPreviewLayer.videoGravity = .resizeAspect

        let animator = UIViewPropertyAnimator(duration: 0.15, curve: .easeInOut) {
            // adjust shutter icon size, by deactivating current constraint and activating alternative constraint defined in storyboard
            if self.portraitMode {
                self.shutterWidthLandscape.isActive = false
                self.shutterWidthPortrait.isActive = true
            } else {
                self.shutterWidthPortrait.isActive = false
                self.shutterWidthLandscape.isActive = true
            }
            self.view.layoutIfNeeded()

            // rotate other visual elements
            self.flipCamera.transform = Orientation.current.CGTransform
            self.flashButton.transform = Orientation.current.CGTransform
            self.zoomLabel.transform = Orientation.current.CGTransform
            self.thumbnail.transform = Orientation.current.CGTransform
        }

        animator.addCompletion { position in
            if position == .end {
                self.cameraConfigQueue.async {
                    captureSession.sessionPreset = .photo
                    self.startAndRemoveBlur(for: captureSession)
                }
            }
            self.resetFocusPoint()
        }

        animator.startAnimation()
    }

    @IBAction func snap(_ sender: UIButton, forEvent event: UIEvent) {
        guard let capturePhotoOutput = self.capturePhotoOutput else { return }
        let supportsHEVC = capturePhotoOutput.availablePhotoCodecTypes.contains(.hevc)

        // from the docs: illegal to reuse AVCapturePhotoSettings object for different captures
        let photoSettings = AVCapturePhotoSettings(format: [
            AVVideoCodecKey: supportsHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.jpeg
        ])
        photoSettings.isHighResolutionPhotoEnabled = true
        if capturePhotoOutput.supportedFlashModes.contains(flashMode) {
            photoSettings.flashMode = flashMode
        }

        capturePhotoOutput.connection(with: .video)?.videoOrientation = Orientation.current.AVOrientation
        let captureObject = PhotoCaptureObject()
        captureObject.completionHandler = { (data, error) in    // we keep a strong reference to `self`, so the captureObject will stay in memory (and complete) even after view controller is deallocated
            defer {
                self.captureObjectsInProgress.mutate{ $0.remove(captureObject) }
            }

            guard error == nil, let data = data else { self.log.error(error ?? "some error with the data"); return }
            guard let originalImage = UIImage(data: data) else { self.log.error("failed to convert captured data to an image"); return }

//            DispatchQueue.main.async {
//                UIView.transition(with: self.thumbnail, duration: 0.5, options: .transitionCrossDissolve, animations: {
//                    self.thumbnail.image = originalImage
//                }, completion: nil)
//            }

            let _ = Asset(
                uuid: UUID(),
                ownerID: self.ownerID,
                creationDate: Date(),
                location: self.locationManager.currentLocation,
                pixelSize: CGSize(width: originalImage.size.width * originalImage.scale, height: originalImage.size.height * originalImage.scale),
                imported: false,    // need to verify this is correct (import component statemachine)
                favourite: false)
//            self.imageManager.importFromCamera(asset, withData: (data, supportsHEVC ? .heic : .jpg), to: self.trip)
        }
        captureObjectsInProgress.mutate{ $0.insert(captureObject) }
        capturePhotoOutput.capturePhoto(with: photoSettings, delegate: captureObject)

        // animate screen flash, for more distinctive shutter
        let animator = UIViewPropertyAnimator(duration: 0.1, curve: .linear) {
            self.mainView.alpha = 0
        }
        animator.addCompletion { _ in
            self.mainView.alpha = 1
        }
        animator.startAnimation()

        // black out thumbnail
        thumbnail.image = nil
    }

    @IBAction func flipCamera(_ sender: Any) {
        guard let captureSession = self.captureSession else { return }

        if let flipAnimator = flipAnimator, flipAnimator.isRunning {
            // mid-way through animation, so reverse it
            flipAnimator.pauseAnimation()
            flipAnimator.isReversed = true
        } else {
            // init new animation
            addBlurAndStop(session: captureSession)

            flipAnimator = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut) {
                UIView.setAnimationTransition(self.frontCameraActive ? .flipFromLeft: .flipFromRight, for: self.mainView, cache: true)
            }
            flipAnimator?.addCompletion { position in
                if position == .end {
                    // completion closure runs on main queue, so any long operations will block the UI, hence spawn async task to handle switching of camera
                    self.cameraConfigQueue.async {
                        let frontCameraActive = self.frontCameraActive
                        guard let previousInput = frontCameraActive ? self.frontCameraInput : self.backCameraInput else { return }
                        guard let captureInput = frontCameraActive ? self.backCameraInput : self.frontCameraInput else { return }

                        captureSession.beginConfiguration()
                        captureSession.removeInput(previousInput)
                        captureSession.sessionPreset = .photo
                        if captureSession.canAddInput(captureInput) {
                            captureSession.addInput(captureInput)
                            self.frontCameraActive = !frontCameraActive
                        } else {
                            self.log.error("unable to add \(frontCameraActive ? "back" : "front") camera input device to the captureSession, reverting to previously used camera")
                            captureSession.addInput(previousInput)
                        }
                        captureSession.commitConfiguration()

                        self.startAndRemoveBlur(for: captureSession)
                    }
                } else {
                    self.startAndRemoveBlur(for: captureSession)
                }
                self.resetFocusPoint()
            }
        }
        flipAnimator?.startAnimation()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @IBAction func loadPhotoViewModally(_ sender: Any) {
//        let storyboard = UIStoryboard(name: "Photo", bundle: nil)
//        let photoVC = storyboard.instantiateInitialViewController() as! PhotoView
//        photoVC.initialise(userID: ownerID, trip: trip, imageManager: imageManager, modal: true, tripObserverRegister: tripObserverRegister)
//        self.present(photoVC, animated: true, completion: nil)
    }

    @IBAction func pinch(_ pinchRecognizer: UIPinchGestureRecognizer) {
        guard let captureDevice = frontCameraActive ? frontCameraInput?.device : backCameraInput?.device else { return }

        switch pinchRecognizer.state {
        case .began:
            startZoomFactor = captureDevice.videoZoomFactor

            if let zoomAnimator = zoomAlphaAnimator, zoomAnimator.isRunning {
                zoomAnimator.stopAnimation(true)
            }
            zoomLabel.text = String(format: "%.1f", startZoomFactor) + " x"
            zoomLabel.alpha = 1.0
        case .changed:
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try captureDevice.lockForConfiguration()
                    let factor = self.startZoomFactor * pinchRecognizer.scale
                    // value range will always be somewhere between 1.0 and 10.0. This is because the min and max zoom factor of device depend on video format, which tend to have ridiculously high zoom factors
                    // so we use the min and max value from the device (format), but if the min is below 1.0, we clamp it to 1.0, and if max is above 10.0 we clamp to 10.0
                    let minZoomFactor = max(1.0, captureDevice.minAvailableVideoZoomFactor)
                    let maxZoomFactor = min(10.0, captureDevice.maxAvailableVideoZoomFactor)
                    let newZoomFactor = max(minZoomFactor, min(factor, maxZoomFactor))
                    captureDevice.videoZoomFactor = newZoomFactor
                    captureDevice.unlockForConfiguration()

                    DispatchQueue.main.async {
                        self.zoomLabel.text = String(format: "%.1f", newZoomFactor) + " x"
                    }
                } catch {
                    self.log.error("failed to lock camera, error: \(error)")
                }
            }
        case .ended:
            zoomAlphaAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .easeInOut) {
                self.zoomLabel.alpha = 0
            }
            zoomAlphaAnimator?.startAnimation()
        default:
            break
        }
    }

    @IBAction func toggleFlash() {
        guard let currentCaptureDevice = frontCameraActive ? frontCameraInput?.device : backCameraInput?.device else { return }
        guard currentCaptureDevice.hasFlash else { return }
        switch flashMode {
        case .off:
            flashMode = .on
            flashButton.setImage(flashIconOn, for: .normal)
        case .on:
            flashMode = .off
            flashButton.setImage(flashIconOff, for: .normal)
        case .auto :
            break   // unimplented for the moment
        @unknown default:
            fatalError(String(describing: flashMode))
        }
    }

    @IBAction func focusTap(_ recognizer: UITapGestureRecognizer) {
        cameraConfigQueue.async {
            guard let currentCaptureDevice = self.frontCameraActive ? self.frontCameraInput?.device : self.backCameraInput?.device, let videoPreviewLayer = self.videoPreviewLayer else { return }
            guard currentCaptureDevice.isFocusPointOfInterestSupported else { return }

            let pointOfTap = recognizer.location(in: self.mainView)

            DispatchQueue.main.async {
                // adjust focus animation center point
                self.focusSquareCenterX.constant = pointOfTap.x - self.mainView.center.x
                self.focusSquareCenterY.constant = pointOfTap.y - self.mainView.center.y
            }

            let pointToFocus = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: pointOfTap)
            do {
                try currentCaptureDevice.lockForConfiguration()
                currentCaptureDevice.focusPointOfInterest = pointToFocus
                currentCaptureDevice.focusMode = .autoFocus
                currentCaptureDevice.unlockForConfiguration()
            } catch {
                self.log.error("unable to set focus point on tap")
            }
        }
    }

    @objc private func resetFocusPoint() {
        cameraConfigQueue.async {
            guard let currentCaptureDevice = self.frontCameraActive ? self.frontCameraInput?.device : self.backCameraInput?.device else { return }
            guard currentCaptureDevice.isFocusPointOfInterestSupported else { return }
            guard currentCaptureDevice.focusPointOfInterest.x != 0.5, currentCaptureDevice.focusPointOfInterest.y != 0.5 else { return }

            DispatchQueue.main.async {
                // reset focus animation center point
                self.focusSquareCenterX.constant = 0
                self.focusSquareCenterY.constant = 0
            }

            do {
                try currentCaptureDevice.lockForConfiguration()
                currentCaptureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                currentCaptureDevice.focusMode = .continuousAutoFocus
                currentCaptureDevice.unlockForConfiguration()
            } catch {
                self.log.error("unable to reset focus point to centre")
            }
        }
    }

    class PhotoCaptureObject: NSObject, AVCapturePhotoCaptureDelegate {
        var completionHandler: (Data?, Error?) -> Void = { _, _ in }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            completionHandler(photo.fileDataRepresentation(), error)
        }
    }
}

//extension CameraView: TripObserver {
//    func updated(_ trip: Trip) {
//        guard trip.uuid == self.trip.uuid else { return }
//        self.trip = trip
//        if let asset = trip.album.lastAsset {
//            imageManager.requestImage(for: asset, delivery: .fast) { image, _ in
//                UIView.transition(with: self.thumbnail, duration: 0.5, options: .transitionCrossDissolve, animations: {
//                    self.thumbnail.image = image
//                }, completion: nil)
//            }
//        }
//    }
//}
