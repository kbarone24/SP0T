//
//  MapSpot.swift
//  Spot
//
//  Created by kbarone on 6/23/20.
//  Copyright © 2020 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import Firebase
import FirebaseFirestoreSwift

struct MapSpot: Identifiable, Codable {
    
    @DocumentID var id: String?
    
    var city: String? = ""
    var founderID: String
    var imageURL: String
    var inviteList: [String]? = []
    var lowercaseName: String?
    var phone: String? = ""
    var poiCategory: String? ///  poi category is a nil value to check on uploadPost for spot v poi
    var postIDs: [String] = []
    var postPrivacies: [String] = []
    var postTimestamps: [Firebase.Timestamp] = []
    var posterDictionary: [String: [String]] = [:]
    var posterIDs: [String] = []
    var posterUsername: String? = ""
    var privacyLevel: String
    var searchKeywords: [String]?
    var spotDescription: String
    var spotLat: Double
    var spotLong: Double
    var spotName: String
    var tagDictionary: [String: Int] = [:]
    var visitorList: [String] = []
    
    //supplemental values
    var checkInTime: Int64?
    var distance: CLLocationDistance = CLLocationDistance()
    var friendVisitors = 0
    var selected: Bool? = false
    var spotImage: UIImage = UIImage()
    var spotScore: Double = 0
    
    enum CodingKeys: String, CodingKey {
        case id
        case city
        case founderID = "createdBy"
        case imageURL
        case inviteList
        case lowercaseName
        case phone
        case poiCategory
        case postIDs
        case postPrivacies
        case postTimestamps
        case posterDictionary
        case posterIDs
        case posterUsername
        case privacyLevel
        case searchKeywords
        case spotDescription = "description"
        case spotLat
        case spotLong
        case spotName
        case tagDictionary
        case visitorList
    }
    
    /// used for nearby spots in choose spot sections on Upload and LocationPicker. Similar logic as get post score
    func getSpotRank(location: CLLocation) -> Double {
        
        var scoreMultiplier = postIDs.isEmpty ? 10.0 : 50.0 /// 5x boost to any spot that has posts at it
        let distance = max(CLLocation(latitude: spotLat, longitude: spotLong).distance(from: location), 1)
        
        if postIDs.count > 0 { for i in 0 ... postIDs.count - 1 {

            var postScore: Double = 10
            
            /// increment for each friend post
            if posterIDs.count <= i { continue }
            if isFriends(id: posterIDs[safe: i] ?? "") { postScore += 5 }

            let timestamp = postTimestamps[safe: i] ?? Timestamp()
            let postTime = Double(timestamp.seconds)
            
            let current = NSDate().timeIntervalSince1970
            let currentTime = Double(current)
            let timeSincePost = currentTime - postTime
            
            /// add multiplier for recent posts
            var factor = min(1 + (1000000 / timeSincePost), 5)
            let multiplier = pow(1.2, factor)
            factor = multiplier
            
            postScore *= factor
            scoreMultiplier += postScore
        } }

        let finalScore = scoreMultiplier/pow(distance, 1.7)
        return finalScore
    }

    func isFriends(id: String) -> Bool {
        let uid: String = Auth.auth().currentUser?.uid ?? "invalid user"
        if id == uid || (UserDataModel.shared.friendIDs.contains(where: {$0 == id}) && !(UserDataModel.shared.adminIDs.contains(id))) { return true }
        return false
    }
}
