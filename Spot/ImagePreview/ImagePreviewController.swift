//
//  ImagePreviewController.swift
//  Spot
//
//  Created by kbarone on 2/27/20.
//  Copyright © 2020 sp0t, LLC. All rights reserved.
//

import CoreLocation
import Firebase
import IQKeyboardManagerSwift
import Mixpanel
import UIKit
import AVKit
import AVFoundation

final class ImagePreviewController: UIViewController {
    enum Mode: Hashable {
        case image
        case video(url: URL)
    }
    
    let uid: String = Auth.auth().currentUser?.uid ?? "invalid user"

    lazy var currentImage = PostImagePreview()
    lazy var nextImage = PostImagePreview()
    lazy var previousImage = PostImagePreview()
    private lazy var dotView = UIView()

    lazy var postButton: UIButton = {
        let button = UIButton()
        button.setTitle("Post", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.titleLabel?.font = UIFont(name: "SFCompactText-Bold", size: 15)
        button.backgroundColor = UIColor(named: "SpotGreen")
        button.layer.cornerRadius = 8
        button.addTarget(self, action: #selector(postTap), for: .touchUpInside)
        return button
    }()

    private(set) lazy var progressMask: UIView = {
        let view = UIView()
        view.backgroundColor = .black.withAlphaComponent(0.7)
        view.isHidden = true
        return view
    }()
    
    private(set) lazy var progressBar = ProgressBar()
    private(set) lazy var postDetailView = PostDetailView()
    private(set) lazy var spotNameButton = PostAccessoryButton(type: .Spot, name: nil)
    private(set) lazy var mapNameButton = PostAccessoryButton(type: .Map, name: UploadPostModel.shared.mapObject?.mapName)

    private(set) lazy var atButton: UIButton = {
        let button = UIButton()
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.setTitle("@", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont(name: "SFCompactText-SemiboldItalic", size: 25)
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 2.5, right: 0)
        button.layer.cornerRadius = 36 / 2
        button.addTarget(self, action: #selector(atTap), for: .touchUpInside)
        button.isHidden = true
        button.clipsToBounds = false
        return button
    }()
    
    private(set) lazy var newSpotNameView = NewSpotNameView()
    var newSpotMask: NewSpotMask?

    var cancelOnDismiss = false
    var newMapMode = false
    var imageObject: ImageObject?
    var videoObject: VideoObject?

    // swipe down to close keyboard
    private(set) lazy var swipeToClose: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(swipeToClose(_:)))
        gesture.isEnabled = false
        return gesture
    }()
    
    // tap to close keyboard
    private(set) lazy var tapToClose: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapToClose(_:)))
        gesture.accessibilityValue = "tap_to_close"
        gesture.isEnabled = false
        return gesture
    }()
    
    private(set) lazy var tapCaption: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(captionTap))
        gesture.accessibilityValue = "caption_tap"
        return gesture
    }()

    private(set) lazy var textView: UITextView = {
        let view = UITextView()
        view.backgroundColor = nil
        view.textColor = .white
        view.font = UIFont(name: "SFCompactText-Semibold", size: 14.5)
        view.alpha = 0.6
        view.tintColor = UIColor(named: "SpotGreen")
        view.text = textViewPlaceholder
        view.returnKeyType = .done
        view.textContainerInset = UIEdgeInsets(top: 10, left: 19, bottom: 14, right: 60)
        view.isScrollEnabled = false
        view.textContainer.maximumNumberOfLines = 6
        view.textContainer.lineBreakMode = .byTruncatingHead
        view.isUserInteractionEnabled = false
        return view
    }()

    private(set) lazy var tagFriendsView = TagFriendsView()
    
    private var player: AVPlayer?

    var mode: Mode = .image // default
    let textViewPlaceholder = "Write a caption..."
    var shouldAnimateTextMask = false // tells keyboardWillChange whether to reposition
    var firstImageBottomConstraint: CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.tag = 2
        setPostInfo()
        addPreviewView()
        addPostDetail()
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: nil) { [weak self] _ in
            self?.player?.seek(to: CMTime.zero)
            self?.player?.play()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setUpNavBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Mixpanel.mainInstance().track(event: "ImagePreviewOpen")
        enableKeyboardMethods()
        
        if mode != .image, player?.timeControlStatus == .paused {
            player?.seek(to: CMTime.zero)
            player?.play()
        } else if player?.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            playVideoOnDelay()
        }

        // for smooth nav bar transition -> black background not removed with animation
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared.enable = true
        disableKeyboardMethods()
        player?.pause()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent {
            resetPostInfo()
            NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: "ImagePreviewRemove")))
        }
    }

    deinit {
        print("deinit")
    }

    func enableKeyboardMethods() {
        cancelOnDismiss = false
        IQKeyboardManager.shared.enableAutoToolbar = false
        IQKeyboardManager.shared.enable = false // disable for textView sticking to keyboard
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
    }

    func disableKeyboardMethods() {
        cancelOnDismiss = true
        IQKeyboardManager.shared.enable = true
        // Ignore comment: deinit wasn't being called because avplayer observer wasn't removed
        NotificationCenter.default.removeObserver(self)
    }

    private func playVideoOnDelay() {
        // video playback hungup on view appear -> likely due to NextPlayer session lag
        // self?.player?.reasonForWaitingToPlay == .evaluatingBufferingRate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let status = self?.player?.timeControlStatus
            if (status == .waitingToPlayAtSpecifiedRate || status == .paused) && !(self?.cancelOnDismiss ?? true) {
                print("fire play on delay")
                self?.player?.play()
                self?.playVideoOnDelay()
            }
        }
    }
    
    func setPostInfo() {
        switch mode {
        case .image:
            setImagePostInfo()
            
        case .video(let url):
            setVideoPostInfo(url: url)
        }
    }

    private func setUpNavBar() {
        navigationController?.setNavigationBarHidden(true, animated: true)
      //  navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.addTransparentBackground()
    }
    
    private func setImagePostInfo() {
        newMapMode = UploadPostModel.shared.mapObject != nil
        var post = UploadPostModel.shared.postObject ?? MapPost(spotID: "", spotName: "", mapID: "", mapName: "")
        var selectedImages: [UIImage] = []
        var frameCounter = 0
        var frameIndexes: [Int] = []
        var aspectRatios: [CGFloat] = []
        var imageLocations: [[String: Double]] = []
        if let imageObject { UploadPostModel.shared.selectedObjects.append(imageObject) }

        // cycle through selected imageObjects and find individual sets of images / frames
        for obj in UploadPostModel.shared.selectedObjects {
            let location = locationIsEmpty(location: obj.rawLocation) ? UserDataModel.shared.currentLocation : obj.rawLocation
            imageLocations.append(["lat": location.coordinate.latitude, "long": location.coordinate.longitude])

            let images = obj.gifMode ? obj.animationImages : [obj.stillImage]
            selectedImages.append(contentsOf: images)
            frameIndexes.append(frameCounter)
            aspectRatios.append(selectedImages[frameCounter].size.height / selectedImages[frameCounter].size.width)

            frameCounter += images.count
        }

        post.frameIndexes = frameIndexes
        post.aspectRatios = aspectRatios
        post.postImage = selectedImages
        post.imageLocations = imageLocations

        let imageLocation = UploadPostModel.shared.selectedObjects.first?.rawLocation ?? UserDataModel.shared.currentLocation
        if !locationIsEmpty(location: imageLocation) {
            post.setImageLocation = true
            post.postLat = imageLocation.coordinate.latitude
            post.postLong = imageLocation.coordinate.longitude
        }

        UploadPostModel.shared.postObject = post
        UploadPostModel.shared.setPostCity()
    }
    
    private func setVideoPostInfo(url: URL) {
        print("set video info")
        newMapMode = UploadPostModel.shared.mapObject != nil
        guard let videoObject else {
            return
        }

        var post = UploadPostModel.shared.postObject ?? MapPost(spotID: "", spotName: "", mapID: "", mapName: "")
        var locations: [[String: Double]] = []
        let location = locationIsEmpty(location: videoObject.rawLocation) ? UserDataModel.shared.currentLocation : videoObject.rawLocation
        
        locations.append(["lat": location.coordinate.latitude, "long": location.coordinate.longitude])
        
        post.imageLocations = locations
        post.videoLocalPath = videoObject.videoPath
        post.postVideo = videoObject.videoData
        post.postImage = [videoObject.thumbnailImage]
        post.aspectRatios = [UserDataModel.shared.maxAspect]
        post.frameIndexes = [0]
        
        let thisLocation = UploadPostModel.shared.selectedObjects.first?.rawLocation ?? UserDataModel.shared.currentLocation
        if !locationIsEmpty(location: thisLocation) {
            post.setImageLocation = true
            post.postLat = thisLocation.coordinate.latitude
            post.postLong = thisLocation.coordinate.longitude
        }
        
        UploadPostModel.shared.postObject = post
        UploadPostModel.shared.setPostCity()
    }

    func addPreviewView() {
        view.backgroundColor = .black
        guard let post = UploadPostModel.shared.postObject else { return }

        switch mode {
        case .image:
            addPreviewPhoto(post)
            
        case .video(let url):
            print("add preview video")
            addPreviewVideo(path: url)
        }

        view.addSubview(postButton)
        postButton.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(15)
            $0.bottom.equalToSuperview().inset(50)
            $0.width.equalTo(94)
            $0.height.equalTo(40)
        }

        view.addSubview(progressMask)
        progressMask.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        progressMask.addSubview(progressBar)
        progressBar.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(50)
            $0.centerY.equalToSuperview()
            $0.height.equalTo(18)
        }

        view.addGestureRecognizer(swipeToClose)
        tapToClose.delegate = self
        view.addGestureRecognizer(tapToClose)
        tapCaption.delegate = self
        view.addGestureRecognizer(tapCaption)
    }
    
    private func addPreviewPhoto(_ post: MapPost) {
        // add initial preview view and buttons

        currentImage = PostImagePreview(frame: .zero, index: post.selectedImageIndex ?? 0, parent: .ImagePreview)
        view.addSubview(currentImage)
        currentImage.configure(mode: .image(post))

        if post.frameIndexes?.count ?? 0 > 1 {
            nextImage = PostImagePreview(frame: .zero, index: (post.selectedImageIndex ?? 0) + 1, parent: .ImagePreview)
            view.addSubview(nextImage)
            nextImage.configure(mode: .image(post))

            previousImage = PostImagePreview(frame: .zero, index: (post.selectedImageIndex ?? 0) - 1, parent: .ImagePreview)
            view.addSubview(previousImage)
            previousImage.configure(mode: .image(post))

            let pan = UIPanGestureRecognizer(target: self, action: #selector(imageSwipe(_:)))
            view.addGestureRecognizer(pan)
            addDotView()
        }
    }
    
    private func addPreviewVideo(path: URL) {
        player = AVPlayer(url: path)
        player?.currentItem?.preferredForwardBufferDuration = 1.0
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height - 105)
        playerLayer.videoGravity = .resizeAspectFill
        self.view.layer.addSublayer(playerLayer)
        player?.play()
    }

    func addDotView() {
        let imageCount = UploadPostModel.shared.postObject?.frameIndexes?.count ?? 0
        let dotWidth = (9 * imageCount) + (5 * (imageCount - 1))
        view.addSubview(dotView)
        dotView.snp.makeConstraints {
            $0.top.equalToSuperview().offset(73)
            $0.height.equalTo(9)
            $0.width.equalTo(dotWidth)
            $0.centerX.equalToSuperview()
        }
        addDots()
    }

    func addDots() {
        dotView.subviews.forEach {
            $0.removeFromSuperview()
        }
        
        for i in 0..<(UploadPostModel.shared.postObject?.frameIndexes?.count ?? 0) {
            let dot = UIView()
            dot.layer.borderColor = UIColor.white.cgColor
            dot.layer.borderWidth = 1
            dot.backgroundColor = i == UploadPostModel.shared.postObject?.selectedImageIndex ?? 0 ? .white : .clear
            dot.layer.cornerRadius = 9 / 2
            
            dotView.addSubview(dot)
            let leading = i * 14
            dot.snp.makeConstraints {
                $0.leading.equalTo(leading)
                $0.top.equalToSuperview()
                $0.width.height.equalTo(9)
            }
        }
    }

    func addPostDetail() {
        view.addSubview(postDetailView)
        postDetailView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(200)
            $0.bottom.equalToSuperview().offset(-105) // hard code bc done button and next button not perfectly aligned
        }

        spotNameButton.addTarget(self, action: #selector(spotTap), for: .touchUpInside)
        spotNameButton.delegate = self
        postDetailView.addSubview(spotNameButton)
        spotNameButton.snp.makeConstraints {
            $0.leading.equalTo(16)
            $0.bottom.equalToSuperview().offset(-6)
            $0.height.equalTo(36)
            $0.trailing.lessThanOrEqualToSuperview().inset(157)
        }

        mapNameButton.addTarget(self, action: #selector(mapTap), for: .touchUpInside)
        mapNameButton.delegate = self
        postDetailView.addSubview(mapNameButton)
        mapNameButton.snp.makeConstraints {
            $0.leading.equalTo(spotNameButton.snp.trailing).offset(9)
            $0.bottom.height.equalTo(spotNameButton)
            $0.trailing.lessThanOrEqualToSuperview().inset(16)
        }

        textView.delegate = self
        postDetailView.addSubview(textView)
        textView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
        //    $0.height.lessThanOrEqualToSuperview().inset(36)
            $0.bottom.equalTo(spotNameButton.snp.top)
        }

        postDetailView.addSubview(atButton)
        atButton.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(15)
            $0.top.equalTo(textView.snp.top).offset(-4)
            $0.height.width.equalTo(36)
        }

        newSpotNameView.isHidden = true
        view.addSubview(newSpotNameView)
        newSpotNameView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(UIScreen.main.bounds.height / 2) // position around center of screen for smooth animation
            $0.height.equalTo(110)
        }

        if UserDataModel.shared.screenSize == 0 && (UploadPostModel.shared.postObject?.postImage.contains(where: { $0.aspectRatio() > 1.45 }) ?? false) {
            addExtraMask()
        }
    }
    
    private func locationIsEmpty(location: CLLocation) -> Bool {
        return location.coordinate.longitude == 0.0 && location.coordinate.latitude == 0.0
    }
}
