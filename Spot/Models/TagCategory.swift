//
//  TagCategory.swift
//  Spot
//
//  Created by Kenny Barone on 12/1/21.
//  Copyright © 2021 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit

struct TagCategory {
    let name: String
    let selected: Bool
    let index: Int

    init(name: String, index: Int) {
        self.name = name
        self.selected = index == 0 /// random selected by default
        self.index = index
    }
}
