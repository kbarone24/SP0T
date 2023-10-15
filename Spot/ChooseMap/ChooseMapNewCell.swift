//
//  ChooseMapNewCell.swift
//  Spot
//
//  Created by Kenny Barone on 10/3/23.
//  Copyright © 2023 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit

class NewMapCell: UITableViewCell {
    private lazy var newMapView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1)
        view.layer.cornerRadius = 10
        return view
    }()
    private lazy var newMapImage = UIImageView(image: UIImage(named: "GreenAddButton"))
    private lazy var label: UILabel = {
        let label = UILabel()
        label.text = "New map"
        label.textColor = UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1)
        label.font = SpotFonts.SFCompactRoundedBold.fontWith(size: 18)
        return label
    }()
    private lazy var subLabel: UILabel = {
        let label = UILabel()
        label.text = "Start a movement"
        label.textColor = UIColor(red: 0.671, green: 0.671, blue: 0.671, alpha: 1)
        label.font = SpotFonts.SFCompactRoundedSemibold.fontWith(size: 14)
        return label
    }()
    private lazy var bottomLine: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.129, green: 0.129, blue: 0.129, alpha: 1)
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(named: "SpotBlack")
        selectionStyle = .none

        contentView.addSubview(newMapView)
        newMapView.snp.makeConstraints {
            $0.leading.equalTo(16)
            $0.centerY.equalToSuperview()
            $0.height.width.equalTo(50)
        }

        newMapView.addSubview(newMapImage)
        newMapImage.snp.makeConstraints {
            $0.centerX.centerY.equalToSuperview()
        }

        contentView.addSubview(label)
        label.snp.makeConstraints {
            $0.leading.equalTo(newMapView.snp.trailing).offset(10)
            $0.bottom.equalTo(newMapView.snp.centerY).offset(-0.5)
        }

        contentView.addSubview(subLabel)
        subLabel.snp.makeConstraints {
            $0.leading.equalTo(label)
            $0.top.equalTo(newMapView.snp.centerY).offset(0.5)
        }

        contentView.addSubview(bottomLine)
        bottomLine.snp.makeConstraints {
            $0.leading.trailing.bottom.equalToSuperview()
            $0.height.equalTo(1)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
