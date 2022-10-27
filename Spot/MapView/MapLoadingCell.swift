//
//  MapLoadingCell.swift
//  Spot
//
//  Created by Oforkanji Odekpe on 10/23/22.
//  Copyright © 2022 sp0t, LLC. All rights reserved.
//

import UIKit

final class MapLoadingCell: UICollectionViewCell {
    var activityIndicator: CustomActivityIndicator!
    var label: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        activityIndicator = CustomActivityIndicator {
            $0.startAnimating()
            contentView.addSubview($0)
        }
        activityIndicator.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.centerY.equalToSuperview().offset(-10)
            $0.width.height.equalTo(30)
        }

        label = UILabel {
            $0.text = "Loading maps"
            $0.textColor = .black.withAlphaComponent(0.5)
            $0.font = UIFont(name: "SFCompactText-Semibold", size: 12)
            $0.textAlignment = .center
            contentView.addSubview($0)
        }
        label.snp.makeConstraints {
            $0.top.equalTo(activityIndicator.snp.bottom).offset(5)
            $0.centerX.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
