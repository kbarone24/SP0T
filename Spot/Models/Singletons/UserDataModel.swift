//
//  UserDataModel.swift
//  Spot
//
//  Created by Kenny Barone on 9/8/21.
//  Copyright © 2021 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import Firebase
import MapboxMaps

/// keep main user data in a singleton to avoid having to pass mapVC too much. Serves the function of the primary global variable
class UserDataModel {
    
    let uid: String = Auth.auth().currentUser?.uid ?? "invalid user"
    static let shared = UserDataModel()
    
    var adminIDs: [String] = []
    var friendIDs: [String] = []
    var friendsList: [UserProfile] = []

    var userInfo: UserProfile!
    var userSpots: [String] = []
    var userCity: String = ""
    
    var screenSize = UIScreen.main.bounds.height < 800 ? 0 : UIScreen.main.bounds.width > 400 ? 2 : 1 /// 0 = iphone8-, 1 = iphoneX + with 375 width, 2 = iPhoneX+ with 414 width
    var largeScreen = UIScreen.main.bounds.width > 800
    var smallScreen = UIScreen.main.bounds.height < 800
    
    var currentLocation: CLLocation!
    var mapView: MapView!
    
    init() {
        userInfo = UserProfile(currentLocation: "", imageURL: "", name: "", userBio: "", username: "")
        userInfo.id = ""
        currentLocation = CLLocation()
    }
    
    func getTopFriends(selectedList: [String]) -> [UserProfile] {
        // get top friends
        let sortedFriends = userInfo.topFriends.sorted(by: {$0.value > $1.value})
        let topFriends = Array(sortedFriends.map({$0.key}))
        var friendObjects: [UserProfile] = []
        
        /// match friend objects to id's
        for friend in topFriends {
            if var object = UserDataModel.shared.friendsList.first(where: {$0.id == friend}) {
                /// match any friends from selected friends for this use of top friends
                object.selected = selectedList.contains(where: {$0 == object.id})
                friendObjects.append(object)
            }
        }
        return friendObjects
    }
        
    func destroy() {
        adminIDs.removeAll()
        friendIDs.removeAll()
        friendsList.removeAll()
        
        userInfo = nil
        userInfo = UserProfile(currentLocation: "", imageURL: "", name: "", userBio: "", username: "")
        userInfo.id = ""
        
        userSpots.removeAll()
        userCity = ""
    }
}
