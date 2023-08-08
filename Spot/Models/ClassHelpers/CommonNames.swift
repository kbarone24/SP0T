//
//  CommonNames.swift
//  Spot
//
//  Created by Kenny Barone on 8/5/23.
//  Copyright © 2023 sp0t, LLC. All rights reserved.
//

import Foundation

enum SpotColors: String {
    case SpotGreen = "SpotGreen"
    case SpotBlack = "SpotBlack"

    var color: UIColor {
        return UIColor(named: rawValue) ?? .clear
    }
}
