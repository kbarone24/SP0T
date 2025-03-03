//
//  FullScreenImageView.swift
//  Spot
//
//  Created by Kenny Barone on 7/18/23.
//  Copyright © 2023 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit
import SDWebImage
import Mixpanel

class FullScreenImageView: UIView {
    private let imageAspect: CGFloat
    private var imageHeight: CGFloat {
        return imageAspect * UIScreen.main.bounds.width
    }
    private lazy var maskBackground: UIView = {
        let view = UIView()
        view.backgroundColor = SpotColors.SpotBlack.color
        view.alpha = 0.0
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(swipeToClose)))
        return view
    }()

    private lazy var imageView: SpotImageView = {
        var view = SpotImageView()
        view.backgroundColor = SpotColors.SpotBlack.color
        view.contentMode = .scaleAspectFill
        view.enableZoom()
        return view
    }()

    private lazy var exitButton: UIButton = {
        let button = UIButton(withInsets: NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        button.setImage(UIImage(named: "WhiteCancelButton"), for: .normal)
        button.addTarget(self, action: #selector(exitTap), for: .touchUpInside)
        return button
    }()

    deinit {
        imageView.image = nil
    }

    init(image: UIImage, urlString: String, imageAspect: CGFloat, initialFrame: CGRect) {
        self.imageAspect = imageAspect
        super.init(frame: .zero)

        Mixpanel.mainInstance().track(event: "ImagePreviewAppeared")

        addSubview(maskBackground)
        maskBackground.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        maskBackground.addSubview(imageView)
        imageView.image = image
        imageView.snp.makeConstraints {
            $0.leading.equalTo(initialFrame.minX)
            $0.top.equalTo(initialFrame.minY)
            $0.width.equalTo(initialFrame.width)
            $0.height.equalTo(initialFrame.height)
        }

        // imageView hasn't loaded yet in main cell, load it here
        if image.size.width < UIScreen.main.bounds.width {
            // got rid of transformer for now because tyler was complaining about image quality -> should keep an eye on this
        //    let transformer = SDImageResizingTransformer(size: CGSize(width: UIScreen.main.bounds.width * 2, height: (UIScreen.main.bounds.height * 2) * imageAspect), scaleMode: .aspectFit)
            imageView.sd_imageIndicator = SDWebImageActivityIndicator.whiteLarge
            imageView.sd_setImage(with: URL(string: urlString), placeholderImage: UIImage(color: .darkGray))
        }

        let minStatusHeight: CGFloat = UserDataModel.shared.screenSize == 2 ? 54 : UserDataModel.shared.screenSize == 1 ? 47 : 20
        let statusHeight = max(window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 20.0, minStatusHeight)

        maskBackground.addSubview(exitButton)
        exitButton.isHidden = true
        exitButton.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(6)
            $0.top.equalToSuperview().offset(statusHeight + 20)
            $0.width.height.equalTo(45)
        }
    }

    func expand() {
        layoutIfNeeded()
        imageView.snp.removeConstraints()
        imageView.snp.makeConstraints {
            $0.leading.trailing.centerY.equalToSuperview()
            $0.height.equalTo(imageHeight)
        }
        UIView.animate(withDuration: 0.2, animations: {
            self.layoutIfNeeded()
            self.maskBackground.alpha = 1.0
        }) { [weak self] _ in
            self?.exitButton.isHidden = false
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
// MARK: actions
extension FullScreenImageView {
    @objc func exitTap() {
        Mixpanel.mainInstance().track(event: "ImagePreviewTapToExit")
        animateOffscreen()
    }

    @objc func swipeToClose(_ gesture: UIPanGestureRecognizer) {
        if imageView.zooming {
            return
        }

        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        if translation.y > 0 || imageView.swipingToExit {
            switch gesture.state {
            case .began:
                imageView.swipingToExit = true
            case .changed:
                maskBackground.transform = CGAffineTransform(translationX: 0, y: translation.y)
            case .ended, .cancelled, .failed:
                let composite = translation.y + velocity.y / 3
                if composite > bounds.height / 2 {
                    Mixpanel.mainInstance().track(event: "ImagePreviewSwipeToExit")
                    self.animateOffscreen()
                } else {
                    self.resetConstraints()
                }
            default:
                return
            }
        }
    }

    private func animateOffscreen() {
        maskBackground.snp.removeConstraints()
        maskBackground.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(imageHeight)
            $0.top.equalTo(self.snp.bottom)
        }
        UIView.animate(withDuration: 0.2, animations: {
            self.layoutIfNeeded()
            self.maskBackground.alpha = 0.0
        }) { [weak self] _ in
            self?.removeFromSuperview()
        }
    }

    private func resetConstraints() {
        UIView.animate(withDuration: 0.2) {
            self.maskBackground.transform = CGAffineTransform(translationX: 0, y: 0)
        }
    }
}
