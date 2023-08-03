//
//  PostImagePreview.swift
//  Spot
//
//  Created by Kenny Barone on 11/2/22.
//  Copyright © 2022 sp0t, LLC. All rights reserved.
//

import UIKit
import AVFoundation

enum PostImageParent: String {
    case ImagePreview
    case ContentPage
}

enum PostPreviewMode: Hashable {
    case image(MapPost)
    case video(MapPost, URL)
}

final class PostImagePreview: PostImageView {
    public var index: Int = 0
    private var parent: PostImageParent
    private lazy var playerView = PlayerView(videoGravity: .resizeAspectFill)

    convenience init() {
        self.init(frame: .zero, index: 0, parent: .ContentPage)
    }

    init(frame: CGRect, index: Int, parent: PostImageParent) {
        self.index = index
        self.parent = parent
        super.init(frame: frame)

        contentMode = .scaleAspectFill
        clipsToBounds = true
        isUserInteractionEnabled = true
        layer.cornerRadius = 5
        layer.masksToBounds = true
        backgroundColor = .black
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerView.player?.currentItem, queue: nil) { [weak self] _ in
            self?.playerView.player?.seek(to: CMTime.zero)
            self?.playerView.player?.play()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerView.player?.currentItem)
        
        playerView.player?.pause()
        playerView.player = nil
    }
    
    func configure(mode: PostPreviewMode) {
        switch mode {
        case .image(let mapPost):
            configureImage(post: mapPost)
            
        case .video(let mapPost, let url):
            configureVideo(post: mapPost, url: url)
        }
    }
    
    private func configureVideo(post: MapPost, url: URL) {
        let player = AVPlayer(url: url)
        playerView.player = player
        snp.removeConstraints()
        addSubview(playerView)
        playerView.snp.makeConstraints { make in
            make.centerY.centerX.equalToSuperview()
            make.width.equalTo(UIScreen.main.bounds.width - 5)
            make.height.equalTo(UIScreen.main.bounds.height - 45)
        }
    }
    
    private func configureImage(post: MapPost) {
        makeConstraints(post: post)
        setCurrentImage(post: post)
    }

    private func makeConstraints(post: MapPost?) {
        /*
        snp.removeConstraints()

        guard let post = post else { return }
        let currentImage = post.postImage[safe: post.frameIndexes?[safe: index] ?? -1] ??
        UIImage(color: .black, size: CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width)) ??
        UIImage()

        let isGif = getGifImages(selectedImages: post.postImage, frameIndexes: post.frameIndexes ?? [], imageIndex: index).count > 1
        let currentAspect = (currentImage.size.height) / (currentImage.size.width)
        let roundedAspect = getRoundedAspectRatio(aspect: currentAspect)
        snp.makeConstraints {
            if roundedAspect == UserDataModel.shared.maxAspect || isGif {
                // stretch full size
                let bottomOffset: CGFloat = parent == .ContentPage ? 0 : -105
                $0.top.equalToSuperview()
                $0.bottom.equalToSuperview().offset(bottomOffset)
            } else {
                // center in view at aspect fill (true height)
                let bottomOffset: CGFloat = parent == .ContentPage ? -5 : -45
                $0.height.equalTo(currentAspect * UIScreen.main.bounds.width)
                $0.centerY.equalToSuperview().offset(bottomOffset)
            }
            if index == post.selectedImageIndex {
                $0.leading.trailing.equalToSuperview()
            } else if index < post.selectedImageIndex ?? 0 { $0.leading.trailing.equalToSuperview().offset(-UIScreen.main.bounds.width)
            } else if index > post.selectedImageIndex ?? 0 { $0.leading.trailing.equalToSuperview().offset(UIScreen.main.bounds.width)
            }
        }

        for sub in subviews { sub.removeFromSuperview() }
        if currentAspect > 1.1 {
            addBottomMask()
            if currentAspect > 1.45 {
                addTopMask()
            }
        }
         */
    }
/*
    private func setImagePreviewConstraints(aspectRatio: CGFloat, post: MapPost) {
        let layoutValues = getImageLayoutValues(imageAspect: aspectRatio)
        let currentHeight = layoutValues.imageHeight
        let bottomConstraint = layoutValues.bottomConstraint

        snp.makeConstraints {
            $0.height.equalTo(currentHeight)
            $0.bottom.equalTo(-bottomConstraint)
            if index == post.selectedImageIndex {
                $0.leading.trailing.equalToSuperview()
            } else if index < post.selectedImageIndex ?? 0 { $0.leading.trailing.equalToSuperview().offset(-UIScreen.main.bounds.width)
            } else if index > post.selectedImageIndex ?? 0 { $0.leading.trailing.equalToSuperview().offset(UIScreen.main.bounds.width)
            }
        }
    }
*/

    private func setCurrentImage(post: MapPost?) {
        /*
        guard let post = post else { return }
        let images = post.postImage
        let frameIndexes = post.frameIndexes ?? []

        animationImages?.removeAll()

        let still = images[safe: frameIndexes[safe: index] ?? -1] ??
        UIImage(color: .black, size: CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width)) ??
        UIImage()

        image = still
        stillImage = still

        let animationImages = getGifImages(selectedImages: images, frameIndexes: post.frameIndexes ?? [], imageIndex: index)
        self.animationImages = animationImages
        animationIndex = 0

        if !animationImages.isEmpty && !activeAnimation {
            animateGIF(directionUp: true, counter: animationIndex)
        }
         */
    }

    func getGifImages(selectedImages: [UIImage], frameIndexes: [Int], imageIndex: Int) -> [UIImage] {
        /// return empty set of images if there's only one image for this frame index (still image), return all images at this frame index if there's more than 1 image
        guard let selectedFrame = frameIndexes[safe: imageIndex] else { return [] }
        guard let selectedImage = selectedImages[safe: selectedFrame] else { return [] }

        if frameIndexes.count == 1 {
            return selectedImages.count > 1 ? selectedImages : []
        } else if frameIndexes.count - 1 == imageIndex {
            return selectedImage != selectedImages.last ? selectedImages.suffix(selectedImages.count - 1 - selectedFrame) : []
        } else {
            let frame1 = frameIndexes[imageIndex + 1]
            return frame1 - selectedFrame > 1 ? Array(selectedImages[selectedFrame...frame1 - 1]) : []
        }
    }

    private func addTopMask() {
        let topMask = UIView()
        addSubview(topMask)
        topMask.snp.makeConstraints {
            $0.leading.trailing.top.equalToSuperview()
            $0.height.equalTo(100)
        }
        let layer = CAGradientLayer()
        layer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 120)
        layer.colors = [
          UIColor(red: 0, green: 0, blue: 0, alpha: 0).cgColor,
          UIColor(red: 0, green: 0, blue: 0.0, alpha: 0.45).cgColor
        ]
        layer.startPoint = CGPoint(x: 0.5, y: 1.0)
        layer.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer.locations = [0, 1]
        topMask.layer.addSublayer(layer)
    }

    override func addBottomMask() {
        let bottomMask = UIView()
        addSubview(bottomMask)
        bottomMask.snp.makeConstraints {
            $0.leading.trailing.bottom.equalToSuperview()
            $0.height.equalTo(120)
        }
        let layer = CAGradientLayer()
        layer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 120)
        layer.colors = [
            UIColor(red: 0, green: 0, blue: 0, alpha: 0.0).cgColor,
            UIColor(red: 0, green: 0, blue: 0, alpha: 0.6).cgColor
        ]
        layer.locations = [0, 1]
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1.0)
        bottomMask.layer.addSublayer(layer)
    }
}
