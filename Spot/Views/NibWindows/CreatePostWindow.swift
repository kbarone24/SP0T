//
//  CreatePostWindow.swift
//  Spot
//
//  Created by Kenny Barone on 2/25/22.
//  Copyright © 2022 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit

class CreatePostWindow: UIView {
    
    @IBOutlet weak var backgroundImage: UIImageView!
    @IBOutlet weak var postImage: UIImageView!
    
    class func instanceFromNib() -> UIView {
        return UINib(nibName: "CreatePostWindow", bundle: nil).instantiate(withOwner: self, options: nil).first as! UIView
    }
}

