//
//  ImageObject.swift
//  Spot
//
//  Created by Kenny Barone on 8/5/21.
//  Copyright © 2021 sp0t, LLC. All rights reserved.
//

import CoreLocation
import Foundation
import Photos
import UIKit

struct ImageObject {
    let id: String
    let asset: PHAsset
    let rawLocation: CLLocation
    var stillImage: UIImage
    let creationDate: Date
    var fromCamera: Bool
}

struct VideoObject {
    let id: String
    let asset: PHAsset
    let thumbnailImage: UIImage
    let videoData: Data?
    let videoPath: URL
    let rawLocation: CLLocation
    let creationDate: Date
    var fromCamera: Bool
}
