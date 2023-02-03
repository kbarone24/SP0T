//
//  ContentViewerSetUp.swift
//  Spot
//
//  Created by Kenny Barone on 2/1/23.
//  Copyright © 2023 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit
import FirebaseStorageUI

extension ContentViewerCell {
    func addDotView() {
        let frameCount = post?.frameIndexes?.count ?? 1
        if frameCount < 2 {
            dotView.snp.updateConstraints {
                $0.height.equalTo(0)
            }
            return
        }
    }

    func addDots() {
        dotView.subviews.forEach {
            $0.removeFromSuperview()
        }

        let frameCount = post?.frameIndexes?.count ?? 1
        let spaces = CGFloat(6 * frameCount)
        let lineWidth = (UIScreen.main.bounds.width - spaces) / CGFloat(frameCount)
        var leading: CGFloat = 0

        for i in 0...(frameCount) - 1 {
            let line = UIView()
            line.backgroundColor = i <= post?.selectedImageIndex ?? 0 ? UIColor(named: "SpotGreen") : UIColor(red: 1, green: 1, blue: 1, alpha: 0.2)
            line.layer.cornerRadius = 1
            dotView.addSubview(line)
            line.snp.makeConstraints {
                $0.top.bottom.equalToSuperview()
                $0.leading.equalTo(leading)
                $0.width.equalTo(lineWidth)
            }
            leading += 7 + lineWidth
        }
    }

    func setLocationView() {
        locationView.stopAnimating()
        for view in locationView.subviews { view.removeFromSuperview() }
        // add map if map exists unless parent == map
        var mapShowing = false
        if let mapName = post?.mapName, mapName != "", parentVC != .Map {
            mapShowing = true

            locationView.addSubview(mapIcon)
            mapIcon.snp.makeConstraints {
                $0.leading.equalToSuperview()
                $0.width.equalTo(15)
                $0.height.equalTo(16)
                $0.centerY.equalToSuperview()
            }

            mapButton.setTitle(mapName, for: .normal)
            locationView.addSubview(mapButton)
            mapButton.snp.makeConstraints {
                $0.leading.equalTo(mapIcon.snp.trailing).offset(6)
                $0.bottom.equalTo(mapIcon).offset(6)
                $0.trailing.lessThanOrEqualToSuperview()
            }

            locationView.addSubview(separatorView)
            separatorView.snp.makeConstraints {
                $0.leading.equalTo(mapButton.snp.trailing).offset(9)
                $0.height.equalToSuperview()
                $0.width.equalTo(2)
            }
        }
        var spotShowing = false
        if let spotName = post?.spotName, spotName != "", parentVC != .Spot {
            // add spot if spot exists unless parent == spot
            spotShowing = true

            locationView.addSubview(spotIcon)
            spotIcon.snp.makeConstraints {
                if mapShowing {
                    $0.leading.equalTo(separatorView.snp.trailing).offset(9)
                } else {
                    $0.leading.equalToSuperview()
                }
                $0.centerY.equalToSuperview().offset(-0.5)
                $0.width.equalTo(14.17)
                $0.height.equalTo(17)
            }

            spotButton.setTitle(spotName, for: .normal)
            locationView.addSubview(spotButton)
            spotButton.snp.makeConstraints {
                $0.leading.equalTo(spotIcon.snp.trailing).offset(6)
                $0.bottom.equalTo(spotIcon).offset(7)
                $0.trailing.lessThanOrEqualToSuperview()
            }
        }
        // always add city
        cityLabel.text = post?.city ?? ""
        locationView.addSubview(cityLabel)
        cityLabel.snp.makeConstraints {
            if spotShowing {
                $0.leading.equalTo(spotButton.snp.trailing).offset(6)
                $0.bottom.equalTo(spotIcon).offset(0.5)
            } else if mapShowing {
                $0.leading.equalTo(separatorView.snp.trailing).offset(9)
                $0.bottom.equalTo(mapIcon).offset(1.0)
            } else {
                $0.leading.equalToSuperview()
                $0.bottom.equalTo(-8)
            }
            $0.trailing.lessThanOrEqualToSuperview()
        }

        // animate location if necessary
        layoutIfNeeded()
        animateLocation()
    }

    func setPostInfo() {
        // add caption and check for more buton after laying out subviews / frame size is determined
        captionLabel.attributedText = NSAttributedString(string: post?.caption ?? "")
        addCaptionAttString()

        // update username constraint with no caption -> will also move prof pic, timestamp
        if post?.caption.isEmpty ?? true {
            profileImage.snp.removeConstraints()
            profileImage.snp.makeConstraints {
                $0.leading.equalTo(14)
                $0.centerY .equalTo(usernameLabel)
                $0.height.width.equalTo(33)
            }
        }
        contentView.layoutSubviews()
        addMoreIfNeeded()

        let transformer = SDImageResizingTransformer(size: CGSize(width: 100, height: 100), scaleMode: .aspectFill)
        profileImage.sd_setImage(with: URL(string: post?.userInfo?.imageURL ?? ""), placeholderImage: nil, options: .highPriority, context: [.imageTransformer: transformer])

        usernameLabel.text = post?.userInfo?.username ?? ""
        timestampLabel.text = post?.timestamp.toString(allowDate: true) ?? ""
    }

    // modify for video
    public func setContentData(images: [UIImage]) {
        if images.isEmpty { return }
        var frameIndexes = post?.frameIndexes ?? []
        if let imageURLs = post?.imageURLs, !imageURLs.isEmpty {
            if frameIndexes.isEmpty { for i in 0...imageURLs.count - 1 { frameIndexes.append(i)} }
            post?.frameIndexes = frameIndexes
            post?.postImage = images

            addImageView()
        }
    }

    public func addCaptionAttString() {
        if let taggedUsers = post?.taggedUsers, !taggedUsers.isEmpty {
            let attString = NSAttributedString.getAttString(caption: post?.caption ?? "", taggedFriends: taggedUsers, font: captionLabel.font, maxWidth: UIScreen.main.bounds.width - 73)
            captionLabel.attributedText = attString.0
            tagRect = attString.1
        }
    }

    private func addMoreIfNeeded() {
        if captionLabel.intrinsicContentSize.height > captionLabel.frame.height {
            moreShowing = true
            captionLabel.addTrailing(with: "... ", moreText: "more", moreTextFont: UIFont(name: "SFCompactText-Semibold", size: 14.5), moreTextColor: .white)
        }
    }

    func addImageView() {
        resetImages()
        currentImage = PostImagePreview(frame: .zero, index: post?.selectedImageIndex ?? 0, parent: .ContentPage)
        contentView.addSubview(currentImage)
        contentView.sendSubviewToBack(currentImage)
        currentImage.makeConstraints(post: post)
        currentImage.setCurrentImage(post: post)

        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTap(_:)))
        currentImage.addGestureRecognizer(tap)

        if post?.frameIndexes?.count ?? 0 > 1 {
            nextImage = PostImagePreview(frame: .zero, index: (post?.selectedImageIndex ?? 0) + 1, parent: .ContentPage)
            contentView.addSubview(nextImage)
            contentView.sendSubviewToBack(nextImage)
            nextImage.makeConstraints(post: post)
            nextImage.setCurrentImage(post: post)

            previousImage = PostImagePreview(frame: .zero, index: (post?.selectedImageIndex ?? 0) - 1, parent: .ContentPage)
            contentView.addSubview(previousImage)
            contentView.sendSubviewToBack(previousImage)
            previousImage.makeConstraints(post: post)
            previousImage.setCurrentImage(post: post)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(imageSwipe(_:)))
            pan.delegate = self
            contentView.addGestureRecognizer(pan)
            addDots()
        }
    }
    // only called after user increments / decrements image
    func setImages() {
        let selectedIndex = post?.selectedImageIndex ?? 0
        currentImage.index = selectedIndex
        currentImage.makeConstraints(post: post)
        currentImage.setCurrentImage(post: post)

        previousImage.index = selectedIndex - 1
        previousImage.makeConstraints(post: post)
        previousImage.setCurrentImage(post: post)

        nextImage.index = selectedIndex + 1
        nextImage.makeConstraints(post: post)
        nextImage.setCurrentImage(post: post)
        addDots()
    }
}
