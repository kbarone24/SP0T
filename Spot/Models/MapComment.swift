//
//  MapComment.swift
//  Spot
//
//  Created by kbarone on 7/22/20.
//  Copyright © 2020 sp0t, LLC. All rights reserved.
//

import Firebase
import FirebaseFirestoreSwift
import Foundation
import UIKit

struct MapComment: Identifiable, Codable, Hashable {

    @DocumentID var id: String?
    var comment: String
    var commenterID: String
    var taggedUsers: [String]? = []
    var timestamp: Firebase.Timestamp
    var likers: [String]? = []

    var userInfo: UserProfile?
    var feedHeight: CGFloat = 0
    var seconds: Int64 {
        return timestamp.seconds
    }

    enum CodingKeys: String, CodingKey {
        case id
        case comment
        case commenterID
        case likers
        case taggedUsers
        case timestamp
    }
}

extension MapComment {
    init(mapComment: MapCommentCache) {
        self.id = mapComment.id
        self.comment = mapComment.comment
        self.commenterID = mapComment.commenterID
        self.taggedUsers = mapComment.taggedUsers
        self.timestamp = mapComment.timestamp ?? Firebase.Timestamp.init(date: Date())
        self.likers = mapComment.likers
        if let userInfo = mapComment.userInfo {
            self.userInfo = UserProfile(from: userInfo)
        } else {
            self.userInfo = nil
        }

        self.feedHeight = CGFloat(mapComment.feedHeight)
    }
}
