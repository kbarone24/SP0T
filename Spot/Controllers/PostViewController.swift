//
//  PostViewController.swift
//  Spot
//
//  Created by kbarone on 1/8/20.
//  Copyright © 2020 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit
import MapKit
import Firebase
import CoreLocation
import Mixpanel
import FirebaseUI

class PostViewController: UIViewController {
    
    lazy var friendsList: [String] = []
    lazy var postsList: [MapPost] = []

    var tableView: UITableView!
    var cellHeight, closedY, tabBarHeight: CGFloat!
    var selectedPostIndex = 0 /// current row in posts table
    var parentVC: parentViewController = .feed
    var vcid = "" /// id of this post controller (in case there is more than 1 active at once)
    let uid: String = Auth.auth().currentUser?.uid ?? "invalid user"
    unowned var mapVC: MapViewController!
    var commentNoti = false /// present commentsVC if opened from notification comment
    
    var editView = false /// edit overview presented
    var editPostView = false /// edit post view presented
    var notFriendsView = false /// not friends view presented
    var editedPost: MapPost! /// selected post with edits
        
    var active = true
    
    private lazy var loadingQueue = OperationQueue()
    private lazy var loadingOperations = [String: PostImageLoader]()
    lazy var currentImageSet: (id: String, images: [UIImage]) = (id: "", images: [])
    
    enum parentViewController {
        case feed
        case spot
        case profile
        case notifications
    }
    
    deinit {
        print("deinit")
    }
  
    override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)
        Mixpanel.mainInstance().track(event: "PostPageOpen")
        
        if tableView == nil {
            vcid = UUID().uuidString
            self.setUpTable()
            
        } else {
            if self.children.count != 0 { return }
            resetView()
            tableView.reloadData()
        }
    }
    
    func cancelDownloads() {
        
        // cancel image loading operations and reset map
        for op in loadingOperations {
            guard let imageLoader = loadingOperations[op.key] else { continue }
            imageLoader.cancel()
            loadingOperations.removeValue(forKey: op.key)
        }
        
        loadingQueue.cancelAllOperations()
        if parentVC != .spot { hideFeedButtons() } /// feed buttons needed for spot page too
        mapVC.mapView.isUserInteractionEnabled = true
    }
    
    func setUpTable() {
        
        let tabBar = mapVC.customTabBar
        let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
        let safeBottom = window?.safeAreaInsets.bottom ?? 0
        
        tabBarHeight = tabBar?.tabBar.frame.height ?? 44 + safeBottom
        closedY = !(tabBar?.tabBar.isHidden ?? false) ? tabBarHeight + 62 : safeBottom + 62
        cellHeight = UIScreen.main.bounds.height > 800 ? (UIScreen.main.bounds.width * 1.77778) : (UIScreen.main.bounds.width * 1.5)
        cellHeight += tabBarHeight
        
        tableView = UITableView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        tableView.tag = 16
        tableView.backgroundColor = nil
        tableView.allowsSelection = false
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.isScrollEnabled = false
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: cellHeight, right: 0)
        tableView.register(PostCell.self, forCellReuseIdentifier: "PostCell")
        tableView.register(LoadingCell.self, forCellReuseIdentifier: "LoadingCell")
        view.addSubview(tableView)
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.tableView.scrollToRow(at: IndexPath(row: self.selectedPostIndex, section: 0), at: .top, animated: false)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(notifyImageChange(_:)), name: Notification.Name("PostImageChange"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyIndexChange(_:)), name: NSNotification.Name("PostIndexChange"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyAddressChange(_:)), name: NSNotification.Name("PostAddressChange"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyPostTap(_:)), name: NSNotification.Name("FeedPostTap"), object: nil)

        if self.commentNoti {
            self.openComments()
            self.commentNoti = false
        }
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(tagSelect(_:)), name: NSNotification.Name("TagSelect"), object: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        active = false
        cancelDownloads()
    }
    
    @objc func notifyImageChange(_ sender: NSNotification) {
        if let info = sender.userInfo as? [String: Any] {
            guard let id = info["id"] as? String else { return }
            if id != vcid { return }
            guard let post = info["post"] as? MapPost else { return }
            
            /// this really just resets the selected image index of the post before reloading data
            postsList[selectedPostIndex] = post
            updateParentImageIndex(post: post)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.tableView.reloadRows(at: [IndexPath(row: self.selectedPostIndex, section: 0)], with: .none)
            }
        }
    }
    
    func updateParentImageIndex(post: MapPost) {
        if let feedVC = parent as? FeedViewController {
            feedVC.postsList[selectedPostIndex] = post
        } else if let profilePostsVC = parent as? ProfilePostsViewController {
            profilePostsVC.postsList[selectedPostIndex] = post
        }
    }
    
    @objc func notifyIndexChange(_ sender: NSNotification) {
        if let info = sender.userInfo as? [String: Any] {
            
            guard let id = info["id"] as? String else { return }
            if id != vcid { return }
            
            ///update from likes or comments
            if let post = info["post"] as? MapPost { self.postsList[selectedPostIndex] = post }
            
            /// animate to next post after vertical scroll
            if let index = info["index"] as? Int {
                selectedPostIndex = index
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.tableView.reloadData()
                    UIView.animate(withDuration: 0.2) { [weak self] in
                        guard let self = self else { return }
                        self.tableView.scrollToRow(at: IndexPath(row: self.selectedPostIndex, section: 0), at: .top, animated: false) }}
            } else {
                /// selected from map - here index represents the selected post's postID
                if let id = info["index"] as? String {
                    if let index = self.postsList.firstIndex(where: {$0.id == id}) {
                        self.selectedPostIndex = index
                        DispatchQueue.main.async {
                            UIView.animate(withDuration: 0.2) { [weak self] in
                                guard let self = self else { return }
                                self.tableView.scrollToRow(at: IndexPath(row: self.selectedPostIndex, section: 0), at: .top, animated: false)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            guard let self = self else { return }
                            self.tableView.reloadData()  }
                    }
                }
            }
        }
    }
    
    @objc func notifyAddressChange(_ sender: NSNotification) {
        // edit post address change
        if let info = sender.userInfo as? [String: Any] {
            
            if editedPost == nil { return }
            guard let coordinate = info["coordinate"] as? CLLocationCoordinate2D else { return }
            
            editedPost.postLat = coordinate.latitude
            editedPost.postLong = coordinate.longitude
            self.editPostView = true 
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.tableView.reloadData()
            }
        }
    }
    
    @objc func notifyPostTap(_ sender: NSNotification) {
        /// deselect annotation so tap works again
        for annotation in mapVC.mapView.selectedAnnotations { mapVC.mapView.deselectAnnotation(annotation, animated: false) }
        openDrawer()
    }
    
    @objc func tagSelect(_ sender: NSNotification) {
        /// selected a tagged user from the map tag table
        if let postCell = tableView.cellForRow(at: IndexPath(row: selectedPostIndex, section: 0)) as? PostCell {
            if postCell.editPostView != nil {
                if let username = sender.userInfo?.first?.value as? String {
                    if let word = postCell.editPostView.postCaption.text?.split(separator: " ").last {
                        if word.hasPrefix("@") {
                            var text = String(postCell.editPostView.postCaption.text.dropLast(word.count - 1))
                            text.append(contentsOf: username)
                            postCell.editPostView.postCaption.text = text
                        }
                    }
                }
            }
        }
    }
    
    func resetView() {
        
        mapVC.postsList = postsList
        mapVC.mapView.isUserInteractionEnabled = false

        ///notify map to show this post
        mapVC.navigationController?.setNavigationBarHidden(true, animated: false)
        
        if parentVC == .notifications {
            if let tabBar = parent?.parent as? CustomTabBar {
                tabBar.view.frame = CGRect(x: 0, y: mapVC.tabBarClosedY, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
            }
            
        } else if parentVC == .feed {
            mapVC.customTabBar.tabBar.isHidden = false
            if selectedPostIndex == 0 && tableView != nil {
                DispatchQueue.main.async { self.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true) }
            }
            
            if let feed = parent as? FeedViewController {
                feed.checkForNewPosts()
            }
        }
        
        let mapPass = ["selectedPost": selectedPostIndex as Any, "firstOpen": true, "parentVC": parentVC] as [String : Any]
        NotificationCenter.default.post(name: Notification.Name("PostOpen"), object: nil, userInfo: mapPass)
    }
    
    func openComments() {
        if let commentsVC = UIStoryboard(name: "Feed", bundle: nil).instantiateViewController(identifier: "Comments") as? CommentsViewController {
            let post = self.postsList[selectedPostIndex]
            commentsVC.commentList = post.commentList
            commentsVC.post = post
            commentsVC.captionHeight = getCaptionHeight(caption: post.caption)
            
            commentsVC.postVC = self
            commentsVC.userInfo = self.mapVC.userInfo
            present(commentsVC, animated: true, completion: nil)
        }
    }
    
    func getCaptionHeight(caption: String) -> CGFloat {
        let tempLabel = UILabel(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 36, height: 20))
        tempLabel.text = caption
        tempLabel.font = UIFont(name: "SFCamera-Regular", size: 12.5)
        tempLabel.numberOfLines = 0
        tempLabel.lineBreakMode = .byWordWrapping
        tempLabel.sizeToFit()
        return tempLabel.frame.height
    }
    
    func closeDrawer() {
                
        guard let post = postsList[safe: selectedPostIndex] else { return }
        let tabBar = mapVC.customTabBar
        let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
        let safeBottom = window?.safeAreaInsets.bottom ?? 0
        let tabBarHeight = tabBar?.tabBar.frame.height ?? 44 + safeBottom

        let closedY = tabBarHeight + 62
        
        let maxZoom: CLLocationDistance = parentVC == .spot ? 300 : 600
        let adjust: CLLocationDistance = 0.00000525 * maxZoom
        let adjustedCoordinate = CLLocationCoordinate2D(latitude: post.postLat - Double(adjust), longitude: post.postLong)
        mapVC.mapView.animatedZoom(zoomRegion: MKCoordinateRegion(center: adjustedCoordinate, latitudinalMeters: maxZoom, longitudinalMeters: maxZoom), duration: 0.3)

        guard let cell = tableView.cellForRow(at: IndexPath(row: selectedPostIndex, section: 0)) as? PostCell else { return }
        UIView.animate(withDuration: 0.15, animations: {
            self.mapVC.customTabBar.view.frame = CGRect(x: 0, y: UIScreen.main.bounds.height - closedY, width: UIScreen.main.bounds.width, height: closedY)
            cell.postImage.frame = CGRect(x: cell.postImage.frame.minX, y: 0, width: cell.postImage.frame.width, height: cell.postImage.frame.height)
            if cell.pullLine != nil { cell.bringSubviewToFront(cell.pullLine) }
            if cell.topView != nil { cell.bringSubviewToFront(cell.topView) }
            if cell.tapButton != nil { cell.bringSubviewToFront(cell.tapButton) }
        })
        
        mapVC.prePanY = UIScreen.main.bounds.height - closedY
        mapVC.mapView.isUserInteractionEnabled = true
        unhideFeedButtons()
    }
    
    func openDrawer() {
        
        guard let post = postsList[safe: selectedPostIndex] else { return }
        let zoomDistance: CLLocationDistance = parentVC == .spot ? 1000 : 100000
        let adjust = 0.00000525 * zoomDistance
        let adjustedCoordinate = CLLocationCoordinate2D(latitude: post.postLat - adjust, longitude: post.postLong)
        mapVC.mapView.animatedZoom(zoomRegion: MKCoordinateRegion(center: adjustedCoordinate, latitudinalMeters: zoomDistance, longitudinalMeters: zoomDistance), duration: 0.3)

        mapVC.removeBottomBar()
        let prePanY = mapVC.customTabBar.tabBar.isHidden ? mapVC.tabBarClosedY : mapVC.tabBarOpenY
        mapVC.prePanY = prePanY
        mapVC.mapView.isUserInteractionEnabled = false
        hideFeedButtons()

        guard let cell = tableView.cellForRow(at: IndexPath(row: selectedPostIndex, section: 0)) as? PostCell else { return }
        UIView.animate(withDuration: 0.15) {
            self.mapVC.customTabBar.view.frame = CGRect(x: 0, y: prePanY!, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height - prePanY!)
            cell.postImage.frame = CGRect(x: cell.postImage.frame.minX, y: cell.imageY, width: cell.postImage.frame.width, height: cell.postImage.frame.height)
            if cell.pullLine != nil { cell.bringSubviewToFront(cell.pullLine) }
            if cell.topView != nil { cell.bringSubviewToFront(cell.topView) }
            if cell.tapButton != nil { cell.bringSubviewToFront(cell.tapButton) }
        }
    }

}

extension PostViewController: UITableViewDelegate, UITableViewDataSource, UITableViewDataSourcePrefetching {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var postCount = postsList.count

        /// increment postCount if added loading cell at the end
        if let postParent = parent as? ProfilePostsViewController {
            if postParent.refresh != .noRefresh { postCount += 1 }
        } else if let postParent = parent as? FeedViewController {
            if postParent.refresh != .noRefresh { postCount += 1 }
        }
        
        return postCount
    }
    
/*   func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? PostCell else { return }
    } */
    
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        guard let cell = cell as? PostCell else { return }
        guard let post = postsList[safe: indexPath.row] else { return }
        
        /// update cell image and related properties on completion
        
        let updateCellImage: ([UIImage]?) -> () = { [weak self] (images) in
            guard let self = self else { return }
            
            if let index = self.postsList.lastIndex(where: {$0.id == post.id}) {
                if indexPath.row != index { return }
            }
        
            if indexPath.row == self.selectedPostIndex { self.currentImageSet = (id: post.id ?? "", images: images ?? []) }
            
            /// on big jumps in scrolling cancellation doesnt seem to always work
            
            if !(tableView.indexPathsForVisibleRows?.contains(indexPath) ?? true) {
                self.loadingOperations.removeValue(forKey: post.id ?? "")
                return
            }
            
            cell.finishImageSetUp(images: images ?? [])
            
            if self.editView && indexPath.row == self.selectedPostIndex && post.posterID == self.uid { cell.addEditOverview() }
            if self.notFriendsView && indexPath.row == self.selectedPostIndex { cell.addNotFriends() }
            
            let edit = self.editedPost == nil ? post : self.editedPost
            if self.editPostView && indexPath.row == self.selectedPostIndex && post.posterID == self.uid { cell.addEditPostView(editedPost: edit!) }

            self.loadingOperations.removeValue(forKey: post.id ?? "")
        }
        
        /// Try to find an existing data loader
        if let dataLoader = loadingOperations[post.id ?? ""] {
            /// Has the data already been loaded?
            if dataLoader.images.count == post.imageURLs.count {

                cell.finishImageSetUp(images: dataLoader.images)
                loadingOperations.removeValue(forKey: post.id ?? "")
            } else {
                /// No data loaded yet, so add the completion closure to update the cell once the data arrives
                dataLoader.loadingCompleteHandler = updateCellImage
            }
        } else {
            /// Need to create a data loaded for this index path
            if indexPath.row == self.selectedPostIndex && self.currentImageSet.id == post.id ?? "" {
                updateCellImage(currentImageSet.images)
                return
            }
                
            let dataLoader = PostImageLoader(post)
                /// Provide the completion closure, and kick off the loading operation
            dataLoader.loadingCompleteHandler = updateCellImage
            loadingQueue.addOperation(dataLoader)
            loadingOperations[post.id ?? ""] = dataLoader
        }
    }
    
    ///https://medium.com/monstar-lab-bangladesh-engineering/tableview-prefetching-datasource-3de593530c4a
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row < self.postsList.count {
            
            let cell = tableView.dequeueReusableCell(withIdentifier: "PostCell") as! PostCell
            let post = postsList[indexPath.row]
            var postsCount = self.postsList.count
            
            /// increment postCount if added loading cell at the end
            if let postParent = parent as? ProfilePostsViewController {
                if postParent.refresh != .noRefresh { postsCount += 1 }
            } else if let postParent = parent as? FeedViewController {
                if postParent.refresh != .noRefresh { postsCount += 1 }
            }

            cell.setUp(post: post, selectedPostIndex: selectedPostIndex, postsCount: postsCount, parentVC: parentVC, vcid: vcid, row: indexPath.row, cellHeight: cellHeight, tabBarHeight: tabBarHeight, closedY: closedY)
            
            ///edit view was getting added on random cells after returning from other screens so this is really a patch fix
            
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "LoadingCell") as! LoadingCell
            cell.setUp(selectedPostIndex: indexPath.row, parentVC: parentVC, vcid: vcid)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return cellHeight
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return cellHeight
    }
    
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            
            if abs(indexPath.row - selectedPostIndex) > 4 { return }
            
            guard let post = postsList[safe: indexPath.row] else { return }
            if let _ = loadingOperations[post.id ?? ""] { return }

            let dataLoader = PostImageLoader(post)
            dataLoader.queuePriority = .high
            loadingQueue.addOperation(dataLoader)
            loadingOperations[post.id ?? ""] = dataLoader
        }
    }
    
    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        
        for indexPath in indexPaths {
            /// I think due to the size of the table, prefetching was being cancelled for way too many rows, some like 1 or 2 rows away from the selected post index. This is kind of a hacky fix to ensure that fetching isn't cancelled when we'll need the image soon
            if abs(indexPath.row - selectedPostIndex) < 4 { return }

            guard let post = postsList[safe: indexPath.row] else { return }

            if let imageLoader = loadingOperations[post.id ?? ""] {
                imageLoader.cancel()
                loadingOperations.removeValue(forKey: post.id ?? "")
            }
        }
    }
    
    func openSpotPage(edit: Bool) {
        
        guard let spotVC = UIStoryboard(name: "SpotPage", bundle: nil).instantiateViewController(withIdentifier: "SpotPage") as? SpotViewController else { return }
        
        let post = postsList[selectedPostIndex]
        
        spotVC.spotID = post.spotID
        spotVC.spotName = post.spotName
        spotVC.mapVC = self.mapVC
        
        if edit { spotVC.editSpotMode = true }

        self.mapVC.postsList.removeAll()
        self.cancelDownloads()
        
        spotVC.view.frame = self.view.frame
        self.addChild(spotVC)
        self.view.addSubview(spotVC.view)
        spotVC.didMove(toParent: self)
        
        //re-enable spot button
        if let cell = self.tableView.cellForRow(at: IndexPath(row: self.selectedPostIndex, section: 0)) as? PostCell {
            if cell.tapButton != nil { cell.tapButton.isEnabled = true }
        }
        
        self.mapVC.prePanY = self.mapVC.halfScreenY
        DispatchQueue.main.async { self.mapVC.customTabBar.view.frame = CGRect(x: 0, y: self.mapVC.halfScreenY, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height - self.mapVC.halfScreenY) }
    }
    
    func exitPosts(swipe: Bool) {
        
        /// posts will always be a child of feed vc
        if parentVC == .feed { return }
        
        self.willMove(toParent: nil)
        
        ///if swipe down, animate view removal
        if !swipe { view.removeFromSuperview() }
        
        if let spotVC = parent as? SpotViewController {
            spotVC.resetView()
        } else if let profileVC = parent as? ProfileViewController {
            profileVC.postRemove()
        } else if let notificationsVC = parent as? NotificationsViewController {
            notificationsVC.resetView()
        }
        
        removeFromParent()
        
        NotificationCenter.default.removeObserver(self, name: Notification.Name("PostImageChange"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PostIndexChange"), object: nil)
        NotificationCenter.default.removeObserver(self,  name: NSNotification.Name("PostAddressChange"), object: nil)
        NotificationCenter.default.removeObserver(self,  name: NSNotification.Name("TagSelect"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("FeedPostTap"), object: nil)
    }
    
    func unhideFeedButtons() {
        mapVC.toggleMapButton.isHidden = false
        mapVC.directionsButton.isHidden = false
        mapVC.directionsButton.addTarget(self, action: #selector(directionsTap(_:)), for: .touchUpInside)
    }
    
    func hideFeedButtons() {
        mapVC.toggleMapButton.isHidden = true
        mapVC.directionsButton.isHidden = true
        mapVC.directionsButton.removeTarget(self, action: #selector(directionsTap(_:)), for: .touchUpInside)
    }
    
    @objc func directionsTap(_ sender: UIButton) {
        Mixpanel.mainInstance().track(event: "PostGetDirections")
        
        guard let post = postsList[safe: selectedPostIndex] else { return }
        UIApplication.shared.open(URL(string: "http://maps.apple.com/?daddr=\(post.postLat),\(post.postLong)")!)
    }
}

class PostCell: UITableViewCell {
    
    var post: MapPost!
    var selectedSpotID: String!
    
    var topView: UIView!
    var pullLine: UIImageView!
    var postImage: UIImageView!
    var postImageNext: UIImageView!
    var postImagePrevious: UIImageView!
    var bottomMask: UIView!
    var exitButton: UIButton!
    var dotView: UIView!
    
    var spotNameBanner: UIView!
    var tapButton: UIButton!
    var targetIcon: UIImageView!
    var spotNameLabel: UILabel!
    var cityLabel: UILabel!
    
    var userView: UIView!
    var profilePic: UIImageView!
    var username: UILabel!
    var timestamp: UILabel!
    var editButton: UIButton!
    
    var postCaption: UILabel!
    var trueCaptionHeight: CGFloat!
    
    var likeButton, commentButton: UIButton!
    var numLikes, numComments: UILabel!
    
    var vcid: String!
    let uid: String = Auth.auth().currentUser?.uid ?? "invalid user"
    let db: Firestore! = Firestore.firestore()
    
    var selectedPostIndex, postsCount: Int!
    var originalOffset: CGFloat!
    
    var cellHeight: CGFloat = 0
    var parentVC: PostViewController.parentViewController!
    lazy var tagRect: [(rect: CGRect, username: String)] = []

    var nextPan, swipe: UIPanGestureRecognizer!
    
    var noAccessFriend: UserProfile!
    var notFriendsView: UIView!
    var postMask: UIView!
    var addFriendButton: UIButton!
    var isOnlyPost = false /// to determine whether to delete entire spot on delete
    
    var editView: UIView!
    var editPostView: EditPostView!
    
    var screenSize = 0 /// 0 = iphone8-, 1 = iphoneX + with 375 width, 2 = iPhoneX+ with 414 width
    var offScreen = false /// off screen to avoid double interactions with first cell being pulled down
    var imageManager: SDWebImageManager!
    var globalRow = 0 /// row in table
    var imageY: CGFloat = 0 /// minY of postImage before moving drawer
    var closedY: CGFloat = 0
    var tabBarHeight: CGFloat = 0

    func setUp(post: MapPost, selectedPostIndex: Int, postsCount: Int, parentVC: PostViewController.parentViewController, vcid: String, row: Int, cellHeight: CGFloat, tabBarHeight: CGFloat, closedY: CGFloat) {
        
        resetTextInfo()

        self.backgroundColor = UIColor(named: "SpotBlack")
        imageManager = SDWebImageManager()
        
        self.post = post
        self.selectedSpotID = post.spotID
        self.selectedPostIndex = selectedPostIndex
        self.postsCount = postsCount
        self.parentVC = parentVC
        self.tag = 16
        self.vcid = vcid
        self.closedY = closedY
        self.tabBarHeight = tabBarHeight
        self.cellHeight = cellHeight
        globalRow = row

        originalOffset = CGFloat(selectedPostIndex) * cellHeight
        screenSize = UIScreen.main.bounds.height < 800 ? 0 : UIScreen.main.bounds.width > 400 ? 2 : 1
                        
        let overflowBound = screenSize == 2 ? cellHeight - tabBarHeight - 116 : cellHeight - tabBarHeight - 105
        /// reset fields so that other cell is completely cleared out
        
        nextPan = UIPanGestureRecognizer(target: self, action: #selector(verticalSwipe(_:)))
        self.addGestureRecognizer(nextPan)
                        
        let minY: CGFloat = screenSize == 0 ? 0 : screenSize == 1 ? 62 : 69
        postImage = UIImageView(frame: CGRect(x: 0, y: minY, width: UIScreen.main.bounds.width, height: overflowBound))
        postImage.image = UIImage(color: UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0))
        postImage.backgroundColor = nil
        postImage.tag = 16
        postImage.clipsToBounds = true
        postImage.layer.cornerRadius = 7.5
        postImage.isUserInteractionEnabled = true
        addSubview(postImage)
        
        /// load non image related post info

        topView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 62))
        topView.backgroundColor = nil
        topView.tag = 16
        let pan = UIPanGestureRecognizer(target: self, action: #selector(topViewSwipe(_:)))
        topView.addGestureRecognizer(pan)
        addSubview(topView)
        
        pullLine = UIImageView(frame: CGRect(x: UIScreen.main.bounds.width/2 - 18, y: 10, width: 36, height: 4.5))
        pullLine.image = UIImage(named: "PullLine")
        topView.addSubview(pullLine)
        
        if post.spotID != "" {
            
            spotNameBanner = UIView(frame: CGRect(x: 8, y: 17, width: UIScreen.main.bounds.width - 16, height: 20))
            spotNameBanner.backgroundColor = nil
            topView.addSubview(spotNameBanner)
            
            targetIcon = UIImageView(frame: CGRect(x: 0, y: 0.5, width: 19, height: 19))
            targetIcon.image = UIImage(named: "PlainSpotIcon")
            targetIcon.isUserInteractionEnabled = false
            spotNameBanner.addSubview(targetIcon)
            
            spotNameLabel = UILabel(frame: CGRect(x: 22, y: 2.5, width: UIScreen.main.bounds.width - 40, height: 14.5))
            spotNameLabel.lineBreakMode = .byTruncatingTail
            spotNameLabel.text = post.spotName ?? ""
            spotNameLabel.textColor = .white
            spotNameLabel.isUserInteractionEnabled = false
            spotNameLabel.font = UIFont(name: "SFCamera-Semibold", size: 13)
            spotNameLabel.sizeToFit()
            
            spotNameBanner.addSubview(spotNameLabel)
            
            cityLabel = UILabel(frame: CGRect(x: 0, y: spotNameLabel.frame.maxY + 4, width: 300, height: 14))
            cityLabel.isUserInteractionEnabled = false
            cityLabel.text = post.city ?? ""
            cityLabel.textColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            cityLabel.font = UIFont(name: "SFCamera-Semibold", size: 12)
            cityLabel.sizeToFit()
            spotNameBanner.addSubview(cityLabel)
            
            spotNameBanner.sizeToFit()
            
            tapButton = UIButton(frame: CGRect(x: 4, y: 14, width: spotNameLabel.frame.width + 30, height: spotNameBanner.frame.height + 8))
            tapButton.backgroundColor = nil
            tapButton.addTarget(self, action: #selector(spotNameTap(_:)), for: .touchUpInside)
            addSubview(tapButton)
        }
        
        if parentVC != .feed {
            exitButton = UIButton(frame: CGRect(x: UIScreen.main.bounds.width - 45, y: 12, width: 35, height: 35))
            exitButton.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
            exitButton.setImage(UIImage(named: "CancelButton"), for: .normal)
            exitButton.addTarget(self, action: #selector(exitPosts(_:)), for: .touchUpInside)
            topView.addSubview(exitButton)
            
            /// resize to avoid overlap
            if spotNameLabel != nil { spotNameLabel.frame = CGRect(x: 22.5, y: 2.5, width: UIScreen.main.bounds.width - 72, height: 14.5) }
        }
        
        var captionHeight = getCaptionHeight(caption: post.caption)
        trueCaptionHeight = captionHeight
        
        ///  overflow to add more button to caption if necessary. 3 lines max for 414 width screens, 2 lines otherwise
        let tabBarHidden = parentVC == .profile || parentVC == .spot
        
        var maxCaption: CGFloat = screenSize == 2 ? 45 : 30
        if tabBarHidden { maxCaption += 30 }
        let overflow = captionHeight > maxCaption
        captionHeight = min(captionHeight, maxCaption)
        
        /// adjust to incrementally move user info / caption down
        var userAdjust: CGFloat = 0
        switch captionHeight {
        case 75:
            userAdjust = 5
        case 30, 45, 60:
            userAdjust = 15 /// either large screen or tabbarhidden or both
        case 15:
            userAdjust = 25
        case 0:
            userAdjust = 45
        default:
            userAdjust = 0
        }
                
        userView = UIView(frame: CGRect(x: 0, y: overflowBound + userAdjust, width: UIScreen.main.bounds.width, height: 26))
        userView.backgroundColor = nil
        addSubview(userView)
        
        profilePic = UIImageView(frame: CGRect(x: 13, y: 0, width: 26, height: 26))
        profilePic.layer.cornerRadius = 12
        profilePic.clipsToBounds = true
        userView.addSubview(profilePic)

        if post.userInfo != nil {
            let url = post.userInfo.imageURL
            if url != "" {
                let transformer = SDImageResizingTransformer(size: CGSize(width: 200, height: 200), scaleMode: .aspectFill)
                profilePic.sd_setImage(with: URL(string: url), placeholderImage: UIImage(color: UIColor(named: "BlankImage")!), options: .highPriority, context: [.imageTransformer: transformer])
            }
        }
        
        username = UILabel(frame: CGRect(x: 45, y: 6, width: 200, height: 16))
        username.text = post.userInfo == nil ? "" : post.userInfo!.username
        username.textColor = UIColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1)
        username.font = UIFont(name: "SFCamera-Semibold", size: 12)
        username.sizeToFit()
        userView.addSubview(username)
        
        let usernameButton = UIButton(frame: CGRect(x: 10, y: 0, width: username.frame.width + 40, height: 25))
        usernameButton.backgroundColor = nil
        usernameButton.addTarget(self, action: #selector(usernameTap(_:)), for: .touchUpInside)
        userView.addSubview(usernameButton)
        
        timestamp = UILabel(frame: CGRect(x: username.frame.maxX + 8, y: 6.5, width: 150, height: 16))
        timestamp.font = UIFont(name: "SFCamera-Regular", size: 12)
        timestamp.textColor = UIColor(red: 0.706, green: 0.706, blue: 0.706, alpha: 1)
        timestamp.text = getTimestamp(postTime: post.timestamp)
        timestamp.sizeToFit()
        userView.addSubview(timestamp)
        
        if post.posterID == self.uid {
            editButton = UIButton(frame: CGRect(x: timestamp.frame.maxX, y: 0, width: 27, height: 27))
            editButton.setImage(UIImage(named: "EditPost"), for: .normal)
            editButton.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
            editButton.addTarget(self, action: #selector(pencilTapped(_:)), for: .touchUpInside)
            userView.addSubview(editButton)
        }
        
        let liked = post.likers.contains(uid)
        let likeImage = liked ? UIImage(named: "UpArrowFilled") : UIImage(named: "UpArrow")
        
        commentButton = UIButton(frame: CGRect(x: UIScreen.main.bounds.width - 112, y: 0, width: 29.5, height: 29.5))
        commentButton.setImage(UIImage(named: "CommentIcon"), for: .normal)
        commentButton.contentMode = .scaleAspectFill
        commentButton.imageEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        commentButton.addTarget(self, action: #selector(commentsTap(_:)), for: .touchUpInside)
        userView.addSubview(commentButton)
        
        numComments = UILabel(frame: CGRect(x: commentButton.frame.maxX + 0.5, y: 6.5, width: 30, height: 15))
        let commentCount = max(post.commentList.count - 1, 0)
        numComments.text = String(commentCount)
        numComments.font = UIFont(name: "SFCamera-Semibold", size: 12.5)
        numComments.textColor = UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.00)
        numComments.textAlignment = .center
        numComments.sizeToFit()
        userView.addSubview(numComments)
        
        likeButton = UIButton(frame: CGRect(x: UIScreen.main.bounds.width - 54, y: 0, width: 29.5, height: 29.5))
        liked ? likeButton.addTarget(self, action: #selector(unlikePost(_:)), for: .touchUpInside) : likeButton.addTarget(self, action: #selector(likePost(_:)), for: .touchUpInside)
        likeButton.setImage(likeImage, for: .normal)
        likeButton.contentMode = .scaleAspectFill
        likeButton.imageEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        userView.addSubview(likeButton)
        
        numLikes = UILabel(frame: CGRect(x: likeButton.frame.maxX + 0.5, y: 6.5, width: 30, height: 15))
        numLikes.text = String(post.likers.count)
        numLikes.font = UIFont(name: "SFCamera-Semibold", size: 12)
        numLikes.textColor = UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.00)
        numLikes.textAlignment = .center
        numLikes.sizeToFit()
        userView.addSubview(numLikes)
        
        postCaption = UILabel(frame: CGRect(x: 16, y: userView.frame.maxY + 7, width: UIScreen.main.bounds.width - 32, height: captionHeight + 0.5))
        postCaption.text = post.caption
        postCaption.textColor = UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
        postCaption.font = UIFont(name: "SFCamera-Regular", size: 12.5)
        
        var numberOfLines = overflow ? screenSize == 2 ? 3 : 2 : 0
        if tabBarHidden && overflow { numberOfLines += 2 }
        postCaption.numberOfLines = numberOfLines
        postCaption.lineBreakMode = overflow ? .byTruncatingTail : .byWordWrapping
        postCaption.isUserInteractionEnabled = true
        
        postCaption.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(captionTap(_:))))
        
        /// adding links for tagged users
        if !(post.taggedUsers?.isEmpty ?? true) {
            let attString = self.getAttString(caption: post.caption, taggedFriends: post.taggedUsers!)
            postCaption.attributedText = attString.0
            tagRect = attString.1
            
            let tap = UITapGestureRecognizer(target: self, action: #selector(self.tappedLabel(_:)))
            postCaption.isUserInteractionEnabled = true
            postCaption.addGestureRecognizer(tap)
        }
        
        if overflow {
            postCaption.addTrailing(with: "... ", moreText: "more", moreTextFont: UIFont(name: "SFCamera-Semibold", size: 12.5)!, moreTextColor: .white)
            addSubview(self.postCaption)
        } else { addSubview(postCaption) }
        
     //   postCaption.sizeToFit()
    }
    
    func finishImageSetUp(images: [UIImage]) {
        resetImageInfo()

        if images.isEmpty { return }
        post.postImage = images
        
        guard let currentImage = post.postImage[safe: post.selectedImageIndex] else {  return }
        
        postImage.image = currentImage
        let isGif = post.gif ?? false

        let im = currentImage
        let aspect = im.size.height / im.size.width
        let trueHeight = aspect * UIScreen.main.bounds.width
        
        let overflowBound = screenSize == 2 ? cellHeight - tabBarHeight - 116 : cellHeight - tabBarHeight - 105
        let standardSize = UIScreen.main.bounds.width * 1.333
        let aliveSize = UIScreen.main.bounds.width * 1.5
        var minY: CGFloat = 0

        /// max height is view size, minHeight is overflow boundary
        let maxHeight = min(aliveSize, trueHeight)
        let minHeight = max(maxHeight, standardSize)
        var adjustedHeight = minHeight
        
        /// height adjustment so that image is either completely full screen or at the overflow bound
        if (adjustedHeight < standardSize + 20) {
            adjustedHeight = standardSize
            minY = screenSize == 0 ? 0 : screenSize == 1 ? 62 : 69
            if adjustedHeight > overflowBound { adjustedHeight = overflowBound } /// crop for small screens
        
        } else {
            adjustedHeight = aliveSize
            minY = 0
        }
        
        imageY = minY
        
        if isGif && post.postImage.count == 5 { postImage.animationImages = post.postImage; postImage.animateGIF(directionUp: true, counter: post.selectedImageIndex)}
        
        postImage.frame = CGRect(x: 0, y: minY, width: UIScreen.main.bounds.width, height: adjustedHeight)
        postImage.contentMode = aspect > 1 ? .scaleAspectFill : .scaleAspectFit
        postImage.tag = 16 
        postImage.enableZoom()
    
        // add top mask to show title if title overlaps image
        if minY == 0 && post.spotID != ""  { postImage.addTopMask() }
        if postImage != nil { bringSubviewToFront(postImage) }
        
        if !isGif {
            postImageNext = UIImageView(frame: CGRect(x: UIScreen.main.bounds.width, y: minY, width: UIScreen.main.bounds.width, height: adjustedHeight))
            postImageNext.clipsToBounds = true
            let nImage = post.selectedImageIndex != post.postImage.count - 1 ?  post.postImage[post.selectedImageIndex + 1] : UIImage()
            let nAspect = nImage.size.height / nImage.size.width > 1
            postImageNext.contentMode = nAspect ? .scaleAspectFill : .scaleAspectFit
            postImageNext.image = nImage
            postImageNext.layer.cornerRadius = 7.5
            addSubview(postImageNext)
            if minY == 0 && post.spotID != "" { postImageNext.addTopMask() }
            
            postImagePrevious = UIImageView(frame: CGRect(x: -UIScreen.main.bounds.width, y: minY, width: UIScreen.main.bounds.width, height: adjustedHeight))
            postImagePrevious.clipsToBounds = true
            let pImage = post.selectedImageIndex > 0 ? post.postImage[post.selectedImageIndex - 1] : UIImage()
            let pAspect = pImage.size.height / pImage.size.width > 1
            postImagePrevious.contentMode = pAspect ? .scaleAspectFill : .scaleAspectFit
            postImagePrevious.image = pImage
            postImagePrevious.layer.cornerRadius = 7.5
            addSubview(postImagePrevious)
            if minY == 0 && post.spotID != "" { postImagePrevious.addTopMask() }
        }
                
        /// bottom mask for image overlay if necessary
        if adjustedHeight > standardSize && screenSize == 0 {
            bottomMask = UIView(frame: CGRect(x: 0, y: minY + standardSize - 28, width: UIScreen.main.bounds.width, height: 129))
            bottomMask.backgroundColor = nil
            let layer0 = CAGradientLayer()
            layer0.frame = bottomMask.bounds
            layer0.colors = [
                UIColor(red: 0, green: 0, blue: 0, alpha: 0).cgColor,
                UIColor(red: 0, green: 0, blue: 0, alpha: 0.01).cgColor,
                UIColor(red: 0, green: 0, blue: 0, alpha: 0.04).cgColor,
                UIColor(red: 0, green: 0, blue: 0, alpha: 0.18).cgColor,
                UIColor(red: 0, green: 0, blue: 0, alpha: 0.43).cgColor,
                UIColor(red: 0, green: 0, blue: 0, alpha: 0.9).cgColor
            ]
            layer0.locations = [0, 0.11, 0.24, 0.43, 0.65, 1]
            layer0.startPoint = CGPoint(x: 0.5, y: 0)
            layer0.endPoint = CGPoint(x: 0.5, y: 1.0)
            bottomMask.layer.addSublayer(layer0)
            addSubview(bottomMask)
        }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:)))
        tap.numberOfTapsRequired = 2
        postImage.addGestureRecognizer(tap)
        
        let count = post.imageURLs.count
        
        if count > 1 && !isGif {
            
            swipe = UIPanGestureRecognizer(target: self, action: #selector(panGesture(_:)))
            postImage.addGestureRecognizer(swipe)
                        
            dotView = UIView(frame: CGRect(x: 0, y: minY + standardSize - 19, width: UIScreen.main.bounds.width, height: 10))
            dotView.backgroundColor = nil
            addSubview(dotView)
            
            var i = 1.0
            
            /// 1/2 of size of dot + the distance between that half and the next dot 
            var xOffset = CGFloat(6 + (Double(count - 1) * 7.5))
            while i <= Double(count) {
                
                let view = UIImageView(frame: CGRect(x: UIScreen.main.bounds.width / 2 - xOffset, y: 0, width: 12, height: 12))
                view.layer.cornerRadius = 6
                
                if i == Double(post.selectedImageIndex + 1) {
                    view.image = UIImage(named: "ElipsesFilled")
                } else {
                    view.image = UIImage(named: "ElipsesUnfilled")
                }
                
                view.contentMode = .scaleAspectFit
                dotView.addSubview(view)
                
                i = i + 1.0
                xOffset = xOffset - 15
            }
        }
        
        /// bring subviews and tap areas above masks
        if topView != nil { bringSubviewToFront(topView) }
        if tapButton != nil { bringSubviewToFront(tapButton) }
        if userView != nil { bringSubviewToFront(userView) }
        if postCaption != nil { bringSubviewToFront(postCaption) }
    }
    
    func resetTextInfo() {
        /// reset for fields that are set before image fetch
        if pullLine != nil { pullLine.image = UIImage() }
        if targetIcon != nil { targetIcon.image = UIImage() }
        if spotNameLabel != nil { spotNameLabel.text = "" }
        if cityLabel != nil { cityLabel.text = "" }
        if exitButton != nil { exitButton.setImage(UIImage(), for: .normal) }
        if profilePic != nil { profilePic.image = UIImage() }
        if username != nil { username.text = "" }
        if timestamp != nil { timestamp.text = "" }
        if editButton != nil { editButton.setImage(UIImage(), for: .normal) }
        if commentButton != nil { commentButton.setImage(UIImage(), for: .normal) }
        if numComments != nil { numComments.text = "" }
        if likeButton != nil { likeButton.setImage(UIImage(), for: .normal) }
        if numLikes != nil { numLikes.text = "" }
        if postCaption != nil { postCaption.text = "" }
        if postImage != nil { postImage.image = UIImage(); postImage.removeFromSuperview() }
        
    }
    
    func resetImageInfo() {
        /// reset for fields that are set after image fetch (right now just called on cell init)
        if bottomMask != nil { bottomMask.removeFromSuperview() }
        if postImageNext != nil { postImageNext.image = UIImage() }
        if postImagePrevious != nil { postImagePrevious.image = UIImage() }
        if notFriendsView != nil { notFriendsView.removeFromSuperview() }
        if addFriendButton != nil { addFriendButton.removeFromSuperview() }
        
        if editView != nil { editView.removeFromSuperview(); editView = nil }
        if editPostView != nil { editPostView.removeFromSuperview(); editPostView = nil }
       
        /// remove top mask
        if postImage != nil { for sub in postImage.subviews { sub.removeFromSuperview() } }
        if postImagePrevious != nil { for sub in postImagePrevious.subviews { sub.removeFromSuperview()} }
        if postImageNext != nil { for sub in postImageNext.subviews { sub.removeFromSuperview()} }
        /// remove dots within dotview
        if dotView != nil {
            for dot in dotView.subviews { dot.removeFromSuperview() }
            dotView.removeFromSuperview()
        }
        
        if postMask != nil {
            for sub in postMask.subviews { sub.removeFromSuperview() }
            postMask.removeFromSuperview()
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()

        if imageManager != nil { imageManager.cancelAll(); imageManager = nil }
        if profilePic != nil { profilePic.sd_cancelCurrentImageLoad() }
        if postImage != nil { postImage.removeFromSuperview(); postImage = nil }
    }
    
    @objc func spotNameTap(_ sender: UIButton) {
        /// get spot level info then open spot page
        
        if parentVC == .spot {
            exitPosts(swipe: false)
            return
        }
        
        sender.isEnabled = false
        if let postVC = self.viewContainingController() as? PostViewController {
                        
            if post.createdBy != self.uid && post.spotPrivacy == "friends" &&  !postVC.mapVC.friendIDs.contains(post.createdBy ?? "") {
                self.addNotFriends()
                sender.isEnabled = true
                return
            }
            postVC.openSpotPage(edit: false)
        }
    }
    
    @objc func pencilTapped(_ sender: UIButton) {
        addEditOverview()
    }
    
    
    @objc func usernameTap(_ sender: UIButton) {
        openProfile(user: post.userInfo)
    }
    
    func openProfile(user: UserProfile) {
        
        if let vc = UIStoryboard(name: "Profile", bundle: nil).instantiateViewController(identifier: "Profile") as? ProfileViewController {
            vc.userInfo = user
            
            if let postVC = self.viewContainingController() as? PostViewController {
                vc.mapVC = postVC.mapVC
                vc.id = user.id!
                
                postVC.mapVC.customTabBar.tabBar.isHidden = true
                postVC.cancelDownloads()
                
                vc.view.frame = postVC.view.frame
                postVC.addChild(vc)
                postVC.view.addSubview(vc.view)
                vc.didMove(toParent: postVC)
            }
        }
    }
    
    @objc func captionTap(_ sender: UITapGestureRecognizer) {
        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.openComments()
        }
    }
    
    @objc func commentsTap(_ sender: UIButton) {
        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.openComments()
        }
    }
    
    func removeGestures() {
        if nextPan != nil { self.removeGestureRecognizer(nextPan) }
        if swipe != nil { self.postImage.removeGestureRecognizer(swipe) }
    }
    
    func getCaptionHeight(caption: String) -> CGFloat {
        let tempLabel = UILabel(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 36, height: 20))
        tempLabel.text = caption
        tempLabel.font = UIFont(name: "SFCamera-Regular", size: 12.5)
        tempLabel.numberOfLines = 0
        tempLabel.lineBreakMode = .byWordWrapping
        tempLabel.sizeToFit()
        return tempLabel.frame.height
    }
    
    
    @objc func exitPosts(_ sender: UIButton) {
        exitPosts(swipe: false)
    }
    
    func exitPosts(swipe: Bool) {
        
        Mixpanel.mainInstance().track(event: "PostPageRemove")
        
        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.exitPosts(swipe: swipe)
        }
    }
    
    
    @objc func tappedLabel(_ sender: UITapGestureRecognizer) {
        
        if let postVC = self.viewContainingController() as? PostViewController {
            for r in tagRect {
                if r.rect.contains(sender.location(in: sender.view)) {
                    // open tag from friends list
                    if let friend = postVC.mapVC.friendsList.first(where: {$0.username == r.username}) {
                        openProfile(user: friend)
                    } else {
                        // open tag from user ID
                        let query = self.db.collection("users").whereField("username", isEqualTo: r.username)
                        query.getDocuments { [weak self] (snap, err) in
                            do {
                                guard let self = self else { return }
                                
                                let userInfo = try snap?.documents.first?.data(as: UserProfile.self)
                                guard var info = userInfo else { return }
                                info.id = snap!.documents.first?.documentID ?? ""
                                self.openProfile(user: info)
                            } catch { return }
                        }
                    }
                } else {
                    postVC.openComments()
                }
            }
        }
    }
    
    @objc func imageTapped(_ sender: UITapGestureRecognizer) {
        if post.likers.contains(self.uid) { return }
        likePost()
    }
    
    @objc func likePost(_ sender: UIButton) {
        likePost()
    }
    
    func likePost() {
        likeButton.setImage(UIImage(named: "UpArrowFilled"), for: .normal)
        
        post.likers.append(self.uid)
        numLikes.text = String(post.likers.count)
        
        let infoPass = ["post": self.post as Any, "id": vcid as Any, "index": self.selectedPostIndex as Any] as [String : Any]
        NotificationCenter.default.post(name: Notification.Name("PostIndexChange"), object: nil, userInfo: infoPass)
        self.likePostDB(post: post)
    }
    
    @objc func unlikePost(_ sender: UIButton) {
        likeButton.setImage(UIImage(named: "UpArrow"), for: .normal)
        
        post.likers.removeAll(where: {$0 == self.uid})
        numLikes.text = String(post.likers.count)
        //update main data source -- send notification to map, update comments
        let infoPass = ["post": self.post as Any, "id": vcid as Any, "index": self.selectedPostIndex as Any] as [String : Any]
        NotificationCenter.default.post(name: Notification.Name("PostIndexChange"), object: nil, userInfo: infoPass)
        self.unlikePostDB(post: post)
    }
    
    @objc func topViewSwipe(_ gesture: UIPanGestureRecognizer) {
        
        guard let postVC = viewContainingController() as? PostViewController else { return }
        let closed = postVC.mapVC.prePanY > 200
        
        let translation = gesture.translation(in: self)
        
        if translation.y < 0 && !closed {
            /// pass through to swipe gesture
            verticalSwipe(gesture)
        } else {
            /// open/close drawer
            offsetDrawer(gesture: gesture)
        }
    }
    
    func offsetDrawer(gesture: UIPanGestureRecognizer) {
        
        guard let postVC = viewContainingController() as? PostViewController else { return }
        let closed = postVC.mapVC.prePanY > 200
        let prePanY = postVC.mapVC.prePanY ?? 0
        let translation = gesture.translation(in: self).y
        let velocity = gesture.velocity(in: self).y

        switch gesture.state {
        
        case .changed:
            ///offset frame
            let newHeight = UIScreen.main.bounds.height - prePanY - translation
            postVC.mapVC.customTabBar.view.frame = CGRect(x: 0, y: prePanY + translation, width: UIScreen.main.bounds.width, height: newHeight)
            
            ///zoom on post
            let closedToStart = prePanY > 200
            let lowestZoom: CGFloat = parentVC == .spot ? 300 : 600
            let highestZoom: CGFloat = parentVC == .spot ? 1000 : 100000
            let initialZoom = closedToStart ? lowestZoom : highestZoom
            let endingZoom = closedToStart ? highestZoom : lowestZoom
            
            /// finalY is either openY or closedY depending on drawer initial state. prePanY already adjusted from map
            let finalY = closedToStart ? parentVC == .feed ? postVC.mapVC.tabBarOpenY : postVC.mapVC.tabBarClosedY : UIScreen.main.bounds.height - closedY
            let currentY = translation + prePanY
            let multiplier = (finalY! - currentY) / (finalY! - prePanY)
            let zoom: CGFloat = multiplier * (initialZoom - endingZoom) + endingZoom
            let finalZoom: CLLocationDistance = CLLocationDistance(min(highestZoom, max(zoom, lowestZoom)))
            
            let adjust = 0.00000525 * finalZoom
            let adjustedCoordinate = CLLocationCoordinate2D(latitude: post.postLat - adjust, longitude: post.postLong)
            
            postVC.mapVC.mapView.setRegion(MKCoordinateRegion(center: adjustedCoordinate, latitudinalMeters: finalZoom, longitudinalMeters: finalZoom), animated: false)
            
            /// move postImage to top of frame
            
            
        case .ended, .cancelled:
            if velocity <= 0 && closed && abs(velocity + translation) > cellHeight * 1/3 {
                postVC.openDrawer()
            } else if velocity >= 0 && !closed && abs(velocity + translation) > cellHeight * 1/3 {
                postVC.closeDrawer()
            } else {
                closed ? postVC.closeDrawer() : postVC.openDrawer()
            }
            
        default:
            return
        }
    }
    
        
    @objc func panGesture(_ gesture: UIPanGestureRecognizer) {
        
        let translation = gesture.translation(in: self)
        guard let postVC = viewContainingController() as? PostViewController else { return }
        
        if postVC.mapVC.prePanY > 200 {
            /// offset drawer if its closed and image stole gesture
            offsetDrawer(gesture: gesture)
            
        } else if abs(translation.y) > abs(translation.x) {
            if postImage.frame.maxX > UIScreen.main.bounds.width || postImage.frame.minX < 0 {
                ///stay with image swipe if image swipe already began
                imageSwipe(gesture: gesture)
            } else {
                verticalSwipe(gesture: gesture)
            }
            
        } else {
            if let tableView = self.superview as? UITableView {
                if tableView.contentOffset.y - originalOffset != 0 {
                    ///stay with vertical swipe if image swipe already began
                    verticalSwipe(gesture)
                } else {
                    imageSwipe(gesture: gesture)
                }
            }
        }
    }
    
    func resetImageFrames() {

        let minY = postImage.frame.minY
        let frameN1 = CGRect(x: -UIScreen.main.bounds.width, y: minY, width: UIScreen.main.bounds.width, height: postImage.frame.height)
        let frame0 = CGRect(x: 0, y: minY, width: UIScreen.main.bounds.width, height: postImage.frame.height)
        let frame1 = CGRect(x: UIScreen.main.bounds.width, y: minY, width: UIScreen.main.bounds.width, height: postImage.frame.height)
        
        if postImageNext != nil { postImageNext.frame = frame1 }
        if postImagePrevious != nil { postImagePrevious.frame = frameN1 }
        postImage.frame = frame0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            let infoPass = ["post": self.post as Any, "id": self.vcid as Any] as [String : Any]
            NotificationCenter.default.post(name: Notification.Name("PostImageChange"), object: nil, userInfo: infoPass)
        }
    }
    
    func imageSwipe(gesture: UIPanGestureRecognizer) {
        /// cancel gesture if zooming
        
        if offScreen { resetPostFrame(); return }
                
        let direction = gesture.velocity(in: self)
        let translation = gesture.translation(in: self)
        
        let minY = postImage.frame.minY
        let frameN1 = CGRect(x: -UIScreen.main.bounds.width, y: minY, width: UIScreen.main.bounds.width, height: postImage.frame.height)
        let frame0 = CGRect(x: 0, y: minY, width: UIScreen.main.bounds.width, height: postImage.frame.height)
        let frame1 = CGRect(x: UIScreen.main.bounds.width, y: minY, width: UIScreen.main.bounds.width, height: postImage.frame.height)
                
        switch gesture.state {
            
        case .changed:
            
            //translate to follow finger tracking
            postImage.transform = CGAffineTransform(translationX: translation.x, y: 0)
            postImageNext.transform = CGAffineTransform(translationX: translation.x, y: 0)
            postImagePrevious.transform = CGAffineTransform(translationX: translation.x, y: 0)
            
        case .ended, .cancelled:
            
            if direction.x < 0 {
                if postImage.frame.maxX + direction.x < UIScreen.main.bounds.width/2 && post.selectedImageIndex < post.imageURLs.count - 1 {
                    //animate to next image
                    UIView.animate(withDuration: 0.2) {
                        self.postImageNext.frame = frame0
                        self.postImage.frame = frameN1
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self = self else { return }
                        self.post.selectedImageIndex += 1
                        let infoPass = ["post": self.post as Any, "id": self.vcid as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostImageChange"), object: nil, userInfo: infoPass)
                        return
                    }
                    
                } else {
                    //return to original state
                    UIView.animate(withDuration: 0.2) { self.resetImageFrames() }
                }
                
            } else {
                
                if postImage.frame.minX + direction.x > UIScreen.main.bounds.width/2 && post.selectedImageIndex > 0 {
                    //animate to previous image
                    UIView.animate(withDuration: 0.2) {
                        self.postImagePrevious.frame = frame0
                        self.postImage.frame = frame1
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self = self else { return }
                        self.post.selectedImageIndex -= 1
                        let infoPass = ["post": self.post as Any, "id": self.vcid as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostImageChange"), object: nil, userInfo: infoPass)
                        return
                    }
                    
                } else {
                    //return to original state
                    UIView.animate(withDuration: 0.2) { self.resetImageFrames() }
                }
            }
        default:
            return
        }
    }
    
    @objc func verticalSwipe(_ gesture: UIPanGestureRecognizer) {
        verticalSwipe(gesture: gesture)
    }
    
    func resetCellFrame() {

        if let tableView = self.superview as? UITableView {
            DispatchQueue.main.async { UIView.animate(withDuration: 0.2) {
                tableView.scrollToRow(at: IndexPath(row: self.selectedPostIndex, section: 0), at: .top, animated: false)
                }
            }
        }
    }
    
    func verticalSwipe(gesture: UIPanGestureRecognizer) {
        
        let direction = gesture.velocity(in: self)
        let translation = gesture.translation(in: self)
        
            
        /// offset drawer if its closed and gesture passed to here
        guard let postVC = viewContainingController() as? PostViewController else { return }
        if postVC.mapVC.prePanY > 200 {
            offsetDrawer(gesture: gesture)
            return
        }

        if offScreen { resetPostFrame(); return }
        if self.postsCount < 2 { return }
        /// cancel on image zoom or swipe
        
        if let tableView = self.superview as? UITableView {
            
            func removeGestures() {
                if let gestures = self.gestureRecognizers {
                    for gesture in gestures {
                        self.removeGestureRecognizer(gesture)
                    }
                }
            }
            
            switch gesture.state {
            
            case .began:
                originalOffset = tableView.contentOffset.y
                
            case .changed:
                tableView.setContentOffset(CGPoint(x: 0, y: originalOffset - translation.y), animated: false)
                
            case .ended, .cancelled:

                if direction.y < 0 {
                    // if we're halfway down the next cell, animate to next cell
                    /// return if at end of posts and theres no loading cell next
                    if self.selectedPostIndex == self.postsCount - 1 { self.resetCellFrame(); return }
                                        
                    if (tableView.contentOffset.y - direction.y > originalOffset + cellHeight/4) && (self.selectedPostIndex < self.postsCount) {
                        self.selectedPostIndex += 1
                        
                        Mixpanel.mainInstance().track(event: "PostPageNextPost", properties: ["postIndex": self.selectedPostIndex])
                        let infoPass = ["index": self.selectedPostIndex as Any, "id": vcid as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostIndexChange"), object: nil, userInfo: infoPass)
                        
                        // send notification to map to change post annotation location
                        let mapPass = ["selectedPost": self.selectedPostIndex as Any, "firstOpen": false, "parentVC": parentVC as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostOpen"), object: nil, userInfo: mapPass)
                        removeGestures()
                        return
                        
                    } else {
                        // return to original state
                        self.resetCellFrame()
                    }
                    
                } else {
                    
                    let offsetTable = tableView.contentOffset.y - direction.y
                    let borderHeight = originalOffset - cellHeight * 3/4

                    if (offsetTable < borderHeight) && self.selectedPostIndex > 0 {
                        /// animate to previous post
                        self.selectedPostIndex -= 1
                        let infoPass = ["index": self.selectedPostIndex as Any, "id": vcid as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostIndexChange"), object: nil, userInfo: infoPass)
                        /// send notification to map to change post annotation location
                        let mapPass = ["selectedPost": self.selectedPostIndex as Any, "firstOpen": false, "parentVC": parentVC as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostOpen"), object: nil, userInfo: mapPass)
                        removeGestures()
                        return
                    } else {
                        // return to original state
                        self.resetCellFrame()
                    }
                }
                
            default:
                return
            }
        }
    }
    
    func resetPostFrame() {
        
        if let postVC = self.viewContainingController() as? PostViewController {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.2) {
                    postVC.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: { [weak self] in
                guard let self = self else { return }
                self.offScreen = false
            })
        }
        /// reset horizontal image scroll if necessary
    }
    
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {

        //only close view on maskView touch
        if editView != nil && touch.view?.isDescendant(of: editView) == true {
            return false
        } else if notFriendsView != nil && touch.view?.isDescendant(of: notFriendsView) == true {
            return false
        } else if editPostView != nil {
            return false
        }
        return true
    }

}

///supplementary view methods
extension PostCell {
    
    //1. not friends methods
    func addNotFriends() {
        
        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.notFriendsView = true
            
            addPostMask(edit: false)
            
            notFriendsView = UIView(frame: CGRect(x: UIScreen.main.bounds.width/2 - 128.5, y: self.frame.height/2 - 119, width: 257, height: 191))
            notFriendsView.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.086, alpha: 1)
            notFriendsView.layer.cornerRadius = 7.5
            postMask.addSubview(notFriendsView)
            
            let friendsExit = UIButton(frame: CGRect(x: notFriendsView.frame.width - 33, y: 4, width: 30, height: 30))
            friendsExit.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
            friendsExit.setImage(UIImage(named: "CancelButton"), for: .normal)
            friendsExit.addTarget(self, action: #selector(exitNotFriends(_:)), for: .touchUpInside)
            notFriendsView.addSubview(friendsExit)
            
            let privacyLabel = UILabel(frame: CGRect(x: 45.5, y: 9, width: 166, height: 18))
            privacyLabel.text = "Privacy"
            privacyLabel.textColor = UIColor(red: 0.706, green: 0.706, blue: 0.706, alpha: 1)
            privacyLabel.font = UIFont(name: "SFCamera-Semibold", size: 13)
            privacyLabel.textAlignment = .center
            notFriendsView.addSubview(privacyLabel)
            
            let privacyDescription = UILabel(frame: CGRect(x: 36.5, y: 31, width: 184, height: 36))
            privacyDescription.text = "Must be friends with this spot’s creator for access"
            privacyDescription.textColor = UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
            privacyDescription.font = UIFont(name: "SFCamera-Regular", size: 13.5)
            privacyDescription.textAlignment = .center
            privacyDescription.numberOfLines = 2
            privacyDescription.lineBreakMode = .byWordWrapping
            notFriendsView.addSubview(privacyDescription)
            
            getUserInfo(userID: post.createdBy!) { [weak self] (userInfo) in
                
                guard let self = self else { return }
                self.noAccessFriend = userInfo
                
                let profilePic = UIImageView(frame: CGRect(x: 93, y: 87, width: 32, height: 32))
                profilePic.image = UIImage()
                profilePic.clipsToBounds = true
                profilePic.contentMode = .scaleAspectFill
                profilePic.layer.cornerRadius = 16
                self.notFriendsView.addSubview(profilePic)
                
                let url = userInfo.imageURL
                if url != "" {
                    let transformer = SDImageResizingTransformer(size: CGSize(width: 200, height: 200), scaleMode: .aspectFill)
                    profilePic.sd_setImage(with: URL(string: url), placeholderImage: UIImage(color: UIColor(named: "BlankImage")!), options: .highPriority, context: [.imageTransformer: transformer])
                }
                
                let username = UILabel(frame: CGRect(x: profilePic.frame.maxX + 7, y: 96, width: 200, height: 16))
                username.text = userInfo.username
                username.textColor = UIColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1)
                username.font = UIFont(name: "SFCamera-Semibold", size: 13)
                username.sizeToFit()
                self.notFriendsView.addSubview(username)
                
                profilePic.frame = CGRect(x: (257 - username.frame.width - 40)/2, y: 87, width: 32, height: 32)
                username.frame = CGRect(x: profilePic.frame.maxX + 7, y: 96, width: username.frame.width, height: 16)
                
                let usernameButton = UIButton(frame: CGRect(x: username.frame.minY, y: 80, width: 40 + username.frame.width, height: 40))
                usernameButton.backgroundColor = nil
                usernameButton.addTarget(self, action: #selector(self.notFriendsUserTap(_:)), for: .touchUpInside)
                self.notFriendsView.addSubview(usernameButton)
                
                self.getFriendRequestInfo { (pending) in
                    if pending {
                        let pendingLabel = UILabel(frame: CGRect(x: 20, y: 145, width: self.notFriendsView.bounds.width - 40, height: 20))
                        pendingLabel.text = "Friend request pending"
                        pendingLabel.textAlignment = .center
                        pendingLabel.font = UIFont(name: "SFCamera-Regular", size: 14)
                        pendingLabel.textColor = UIColor(named: "SpotGreen")
                        self.notFriendsView.addSubview(pendingLabel)
                    } else {
                        self.addFriendButton = UIButton(frame: CGRect(x: 33, y: 136, width: 191, height: 45))
                        self.addFriendButton.setImage(UIImage(named: "AddFriendButton"), for: .normal)
                        self.addFriendButton.addTarget(self, action: #selector(self.addFriendTap(_:)), for: .touchUpInside)
                        self.notFriendsView.addSubview(self.addFriendButton)
                    }
                }
            }
        }
    }
    
    func getUserInfo(userID: String, completion: @escaping (_ userInfo: UserProfile) -> Void) {
        self.db.collection("users").document(userID).getDocument { (snap, err) in
            do {
                let userInfo = try snap?.data(as: UserProfile.self)
                guard var info = userInfo else { return }
                info.id = snap!.documentID
                completion(info)
            } catch { return }
        }
    }
    
    
    func getFriendRequestInfo(completion: @escaping(_ pending: Bool) -> Void) {
        let userRef = self.db.collection("users").document(self.uid).collection("notifications")
        let userQuery = userRef.whereField("type", isEqualTo: "friendRequest").whereField("senderID", isEqualTo: self.noAccessFriend.id!)
        
        var zeroCount = 0
        userQuery.getDocuments { (snap, err) in
            
            if err != nil { return }
            
            if snap!.documents.count > 0 {
                completion(true)
            } else {
                zeroCount += 1
                if zeroCount == 2 { completion(false) }
            }
        }
        
        let notiRef = self.db.collection("users").document(self.noAccessFriend.id!).collection("notifications")
        let query = notiRef.whereField("type", isEqualTo: "friendRequest").whereField("senderID", isEqualTo: self.uid)
        query.getDocuments { (snap2, err) in
            
            if err != nil { return }
            
            if snap2!.documents.count > 0 {
                completion(true)
            } else {
                zeroCount += 1
                if zeroCount == 2 { completion(false) }
            }
        }
    }
    
    @objc func tapExitNotFriends(_ sender: UIButton) {
        exitNotFriends()
    }
    
    @objc func exitNotFriends(_ sender: UIButton) {
        exitNotFriends()
    }
    
    func exitNotFriends() {
        
        for sub in notFriendsView.subviews {
            sub.removeFromSuperview()
        }
        
        notFriendsView.removeFromSuperview()
        postMask.removeFromSuperview()
        
        if notFriendsView != nil { notFriendsView = nil }
        
        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.notFriendsView = false
        }
    }
    
    @objc func notFriendsUserTap(_ sender: UIButton) {
        if noAccessFriend != nil {
            openProfile(user: noAccessFriend)
            exitNotFriends()
        }
    }
    
    @objc func addFriendTap(_ sender: UIButton) {
        self.addFriendButton.isHidden = true
        
        let pendingLabel = UILabel(frame: CGRect(x: 20, y: 145, width: notFriendsView.bounds.width - 40, height: 20))
        pendingLabel.text = "Friend request pending"
        pendingLabel.textAlignment = .center
        pendingLabel.font = UIFont(name: "SFCamera-Regular", size: 14)
        pendingLabel.textColor = UIColor(named: "SpotGreen")
        notFriendsView.addSubview(pendingLabel)
        
        if let mapVC = self.parentContainerViewController() as? MapViewController {
            addFriend(senderProfile: mapVC.userInfo, receiverID: self.noAccessFriend.id!)
        }
    }
    
    func addPostMask(edit: Bool) {
        
        postMask = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        postMask.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        let tap = edit ? UITapGestureRecognizer(target: self, action: #selector(tapExitEditOverview(_:))) : UITapGestureRecognizer(target: self, action: #selector(tapExitNotFriends(_:)))
        tap.delegate = self
        postMask.addGestureRecognizer(tap)

        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.mapVC.view.addSubview(postMask)
        }
    }
    
    //2. editOverview
    
    func addEditOverview() {
        
        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.editView = true
        }
        
        editView = UIView(frame: CGRect(x: UIScreen.main.bounds.width/2 - 102, y: UIScreen.main.bounds.height/2 - 119, width: 204, height: 110))
        editView.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.086, alpha: 1)
        editView.layer.cornerRadius = 7.5
        
        addPostMask(edit: true)
        
        postMask.addSubview(editView)
        
        let postExit = UIButton(frame: CGRect(x: editView.frame.width - 33, y: 4, width: 30, height: 30))
        postExit.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        postExit.setImage(UIImage(named: "CancelButton"), for: .normal)
        postExit.addTarget(self, action: #selector(exitEditOverview(_:)), for: .touchUpInside)
        editView.addSubview(postExit)
        
        let editPost = UIButton(frame: CGRect(x: 41, y: 47, width: 116, height: 35))
        editPost.setImage(UIImage(named: "EditPostButton"), for: .normal)
        editPost.backgroundColor = nil
        editPost.addTarget(self, action: #selector(editPostTapped(_:)), for: .touchUpInside)
        editPost.imageView?.contentMode = .scaleAspectFit
        editView.addSubview(editPost)
        
        ///expand the edit view frame to include a delete button if this post can be deleted
        editView.frame = CGRect(x: editView.frame.minX, y: editView.frame.minY, width: editView.frame.width, height: 171)
        
        let deleteButton = UIButton(frame: CGRect(x: 46, y: 100, width: 112, height: 29))
        deleteButton.setImage(UIImage(named: "DeletePostButton"), for: UIControl.State.normal)
        deleteButton.backgroundColor = nil
        deleteButton.addTarget(self, action: #selector(deleteTapped(_:)), for: .touchUpInside)
        editView.addSubview(deleteButton)
    }
    
    @objc func exitEditOverview(_ sender: UIButton) {
        exitEditOverview()
    }
        
    func exitEditOverview() {
        
        if editView != nil {
            for sub in editView.subviews {
                sub.removeFromSuperview()
            }
            editView.removeFromSuperview()
            editView = nil
        }
                
        postMask.removeFromSuperview()
        
        if let postVC = self.viewContainingController() as? PostViewController {
            postVC.editView = false
            postVC.editPostView = false
            postVC.mapVC.removeTable()
        }
    }
    
    @objc func tapExitEditOverview(_ sender: UITapGestureRecognizer) {
        exitEditOverview()
    }

    @objc func editPostTapped(_ sender: UIButton) {
        addEditPostView(editedPost: post)
    }
    
    //3. edit post view (handled by custom class)
    func addEditPostView(editedPost: MapPost) {

        if editPostView != nil && editPostView.superview != nil { return }
        Mixpanel.mainInstance().track(event: "EditPostOpen")
        
        let viewHeight: CGFloat = post.spotID == "" ? 348 : 410
        editPostView = EditPostView(frame: CGRect(x: (UIScreen.main.bounds.width - 331)/2, y: UIScreen.main.bounds.height/2 - 220, width: 331, height: viewHeight))
        
        if postMask == nil { self.addPostMask(edit: true) }
        
        if let postVC = self.viewContainingController() as? PostViewController {
            
            if postMask.superview == nil {
                ///post mask removed from view on transition to address picker
                postVC.mapVC.view.addSubview(postMask)
            }
            postMask.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            
            postMask.addSubview(editPostView)
            
            if editView != nil { editView.removeFromSuperview() }
            
            postVC.editedPost = editedPost
            postVC.editView = false
            postVC.editPostView = true
            editPostView.setUp(post: editedPost, postVC: postVC)
        }
    }
    
    //4. post delete
    
    @objc func deleteTapped(_ sender: UIButton) {
        
        post.isFirst ?? false ? checkForZero() : presentDeleteMenu(message: "")
            /// not ideal to be loading information right on tap but not a better alternative for  when post is only at a spot
    }
    
    func checkForZero() {
        
        let singlePostMessage = "Deleting the only post at a spot will delete the entire spot"
        if post.spotID == nil || post.privacyLevel == "public" { presentDeleteMenu(message: ""); return }
        
        if parentVC == .spot {
            guard let postVC = self.viewContainingController() as? PostViewController else { return }
            guard let spotVC = postVC.parent as? SpotViewController else { return }
            spotVC.postsList.count > 1 ? self.presentDeleteMenu(message: "") : self.presentDeleteMenu(message: singlePostMessage)
            return
        }
        
        self.db.collection("spots").document(post.spotID!).collection("feedPost").getDocuments { (snap, err) in
            snap?.documents.count ?? 0 > 1 ? self.presentDeleteMenu(message: "") : self.presentDeleteMenu(message: singlePostMessage)
        }
    }
    
    func presentDeleteMenu(message: String) {
        if message != "" { isOnlyPost = true }
        if let postVC = self.viewContainingController() as? PostViewController {
            
            let alert = UIAlertController(title: "Delete Post?", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { action in
                switch action.style{
                case .default:
                    ///remove edit view
                    postVC.tableView.reloadData()
                case .cancel:
                    print("cancel")
                case .destructive:
                    print("destruct")
                @unknown default:
                    fatalError()
                }}))
            
            alert.addAction(UIAlertAction(title: "Delete", style: .default, handler: { action in
                switch action.style{
                case .default:
                    postVC.mapVC.deletedPostIDs.append(self.post.id!)
                    ///update database
                    self.postDelete(deletePost: self.post!)
                    Mixpanel.mainInstance().track(event: "PostPagePostDelete")
                    ///update postVC
                    ///send notification
                    let infoPass: [String: Any] = ["postID": self.post.id as Any]
                    NotificationCenter.default.post(name: Notification.Name("DeletePost"), object: nil, userInfo: infoPass)
                    
                case .cancel:
                    print("cancel")
                case .destructive:
                    print("destruct")
                @unknown default:
                    fatalError()
                }}))
            
            editView.removeFromSuperview()
            postMask.removeFromSuperview()
            postVC.editView = false
            postVC.present(alert, animated: true, completion: nil)
        }

    }
    
    
    func postDelete(deletePost: MapPost) {
        
        let postNotiRef = self.db.collection("users").document(deletePost.posterID).collection("notifications")
        let query = postNotiRef.whereField("postID", isEqualTo: deletePost.id!)
        
        query.getDocuments {(querysnapshot, err) in

            for doc in querysnapshot!.documents {
                doc.reference.delete()
            }
        }
        
        if deletePost.createdBy != nil {
            let spotNotiRef = self.db.collection("users").document(deletePost.createdBy!).collection("notifications")
            let spotQuery = spotNotiRef.whereField("postID", isEqualTo: deletePost.id!)
            spotQuery.getDocuments {(querysnapshot, err) in
                
                for doc in querysnapshot!.documents {
                    doc.reference.delete()
                }
            }
        }
        
        self.incrementSpotScore(user: self.uid, increment: -3)
        
        //delete from posts collection
        
        let postRef = self.db.collection("posts").document(deletePost.id!)
        
        postRef.collection("comments").getDocuments { (querysnapshot, err) in
            for doc in querysnapshot!.documents {
                postRef.collection("comments").document(doc.documentID).delete()
                if doc == querysnapshot!.documents.last { postRef.delete() }
            }
            
            if deletePost.spotID != "" {
                let feedPostRef = self.db.collection("spots").document(deletePost.spotID!).collection("feedPost").document(deletePost.id!)
                feedPostRef.collection("Comments").getDocuments { (querysnapshot, err) in
                    for doc in querysnapshot!.documents {
                        postRef.collection("Comments").document(doc.documentID).delete()
                        if doc == querysnapshot!.documents.last {
                            feedPostRef.delete()
                            if self.isOnlyPost { self.spotDelete(spotID: deletePost.spotID!) }
                        }
                    }
                }
                
                
                //remove from user's post list
                var postsCount = 1
                
                let ref = self.db.collection("users").document(self.uid).collection("spotsList").document(deletePost.spotID!)
                self.db.runTransaction({ (transaction, errorPointer) -> Any? in
                    let spotDoc: DocumentSnapshot
                    do {
                        try spotDoc = transaction.getDocument(ref)
                    } catch let fetchError as NSError {
                        errorPointer?.pointee = fetchError
                        return nil
                    }
                    
                    
                    var postsList: [String] = []
                    
                    postsList = spotDoc.data()?["postsList"] as! [String]
                    
                    postsList.removeAll(where: {$0 == deletePost.id})
                    postsCount = postsList.count
                    
                    transaction.updateData([
                        "postsList": postsList
                    ], forDocument: ref)
                    
                    return nil
                    
                }) { (object, error) in
                    if error == nil {
                        if postsCount == 0 { self.removeFromUserSpots(id: deletePost.spotID!, spotDelete: self.isOnlyPost) }
                    }
                }
            }
        }
    }
    
    func spotDelete(spotID: String) {
        self.incrementSpotScore(user: self.uid, increment: -3)
        self.db.collection("spots").document(spotID).delete()
        if let postVC = self.viewContainingController() as? PostViewController {
            if let spotVC = postVC.parent as? SpotViewController {
                spotVC.animateToRoot()
            }
        }
    }
    
    func removeFromUserSpots(id: String, spotDelete: Bool) {
        self.db.collection("users").document(self.uid).collection("spotsList").document(id).delete()
        NotificationCenter.default.post(name: NSNotification.Name("UserListRemove"), object: nil, userInfo: ["spotID" : id])
        
        if spotDelete { return }
        
        //remove user from spots visitor list
        let ref = self.db.collection("spots").document(id)
        self.db.runTransaction({ (transaction, errorPointer) -> Any? in
            let spotDoc: DocumentSnapshot
            do {
                try spotDoc = transaction.getDocument(ref)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            var visitorList = spotDoc.data()?["visitorList"] as! [String]
            visitorList.removeAll(where: {$0 == self.uid})
            
            transaction.updateData([
                "visitorList": visitorList
            ], forDocument: ref)
            
            return nil
            
        }) { _,_ in  }
    }
}


class LoadingCell: UITableViewCell {
    
    var activityIndicator: CustomActivityIndicator!
    var selectedPostIndex: Int!
    var originalOffset: CGFloat!
    var parentVC: PostViewController.parentViewController!
    var vcid: String!
    
    func setUp(selectedPostIndex: Int, parentVC: PostViewController.parentViewController, vcid: String) {
        self.backgroundColor = UIColor(named: "SpotBlack")
        self.selectedPostIndex = selectedPostIndex
        self.parentVC = parentVC
        self.vcid = vcid
        self.originalOffset = 0.0

        self.tag = 16
        
        if activityIndicator != nil { activityIndicator.removeFromSuperview() }
        activityIndicator = CustomActivityIndicator(frame: CGRect(x: 0, y: 100, width: UIScreen.main.bounds.width, height: 40))
        activityIndicator.startAnimating()
        self.addSubview(activityIndicator)
        
        let nextPan = UIPanGestureRecognizer(target: self, action: #selector(verticalSwipe(_:)))
        self.addGestureRecognizer(nextPan)
    }
    
    @objc func verticalSwipe(_ gesture: UIPanGestureRecognizer) {
        let direction = gesture.velocity(in: self)
        let translation = gesture.translation(in: self)
        
        if let tableView = self.superview as? UITableView {
            
            func resetCell() {
                DispatchQueue.main.async { UIView.animate(withDuration: 0.2) {
                    tableView.scrollToRow(at: IndexPath(row: self.selectedPostIndex, section: 0), at: .top, animated: false) }
                }
            }
            
            func removeGestures() {
                if let gestures = self.gestureRecognizers {
                    for gesture in gestures {
                        self.removeGestureRecognizer(gesture)
                    }
                }
            }
            switch gesture.state {
            
            case .began:
                originalOffset = tableView.contentOffset.y
                
            case .changed:
                tableView.setContentOffset(CGPoint(x: 0, y: originalOffset - translation.y), animated: false)
                
            case .ended, .cancelled:
                if direction.y < 0 {
                    resetCell()
                } else {
                    let offsetTable = tableView.contentOffset.y - direction.y
                    let borderHeight = originalOffset - self.bounds.height * 3/4
                    if (offsetTable < borderHeight) && self.selectedPostIndex > 0 {
                        //animate to previous post
                        self.selectedPostIndex -= 1
                        let infoPass = ["index": self.selectedPostIndex as Any, "id": vcid as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostIndexChange"), object: nil, userInfo: infoPass)
                        // send notification to map to change post annotation location
                        let mapPass = ["selectedPost": self.selectedPostIndex as Any, "firstOpen": false, "parentVC": parentVC as Any] as [String : Any]
                        NotificationCenter.default.post(name: Notification.Name("PostOpen"), object: nil, userInfo: mapPass)
                        removeGestures()
                        return
                    } else {
                        // return to original state
                        resetCell()
                    }
                }
            default:
                return
            }
        }
    }
}


class EditPostView: UIView, UITextViewDelegate {
    
    var postingToView: UIView!
    var spotNameLabel: UILabel!
    var captionView: UIView!
    var postImage: UIImageView!
    var postCaption: UITextView!
    var locationView: UIView!
    var addressButton: UIButton!
    var editAddress: UIButton!
    var whoCanSee: UILabel!
    var privacyView: UIView!
    var friendCount: UILabel!
    var actionArrow: UIButton!
    var privacyIcon: UIImageView!
    var privacyLabel: UILabel!
    var privacyMask: UIView!
    
    var post: MapPost!
    weak var postVC: PostViewController!
    var newPrivacy: String!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.086, alpha: 1)
        layer.cornerRadius = 12
    }
    
    func setUp(post: MapPost, postVC: PostViewController) {
        
        self.post = post
        self.postVC = postVC
        
        if post.spotID != "" {
            postingToView = UIView(frame: CGRect(x: 0, y: 0, width: self.bounds.width, height: 62))
            postingToView.backgroundColor = nil
            self.addSubview(postingToView)
            
            let postingToLabel = UILabel(frame: CGRect(x: 14, y: 14, width: 65, height: 15))
            postingToLabel.text = "Posting to"
            postingToLabel.textColor = UIColor(red: 0.706, green: 0.706, blue: 0.706, alpha: 1)
            postingToLabel.font = UIFont(name: "SFCamera-Regular", size: 12.5)
            postingToView.addSubview(postingToLabel)
            
            let targetIcon = UIImageView(frame: CGRect(x: 14, y: 34, width: 17, height: 17))
            targetIcon.image = UIImage(named: "PlainSpotIcon")
            postingToView.addSubview(targetIcon)
            
            spotNameLabel = UILabel(frame: CGRect(x: targetIcon.frame.maxX + 6, y: 35, width: 200, height: 17))
            spotNameLabel.text = post.spotName
            spotNameLabel.textColor = UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
            spotNameLabel.font = UIFont(name: "SFCamera-Regular", size: 12.5)
            spotNameLabel.sizeToFit()
            postingToView.addSubview(spotNameLabel)
            
            if post.createdBy == postVC.uid {
                let editSpotButton = UIButton(frame: CGRect(x: spotNameLabel.frame.maxX + 2, y: 36, width: 55, height: 15))
                editSpotButton.setTitle("EDIT SPOT", for: .normal)
                editSpotButton.setTitleColor(UIColor(named: "SpotGreen"), for: .normal)
                editSpotButton.titleLabel?.font = UIFont(name: "SFCamera-Regular", size: 9.5)
                editSpotButton.addTarget(self, action: #selector(editSpotTap(_:)), for: .touchUpInside)
                postingToView.addSubview(editSpotButton)
                
                let bottomLine = UIView(frame: CGRect(x: 0, y: 61, width: UIScreen.main.bounds.width, height: 1))
                bottomLine.backgroundColor = UIColor(red: 0.179, green: 0.179, blue: 0.179, alpha: 1)
                postingToView.addSubview(bottomLine)
            }
        }
        
        let rollingY: CGFloat = post.spotID == "" ? 0 : 62
        
        captionView = UIView(frame: CGRect(x: 0, y: rollingY, width: self.bounds.width, height: 183))
        captionView.backgroundColor = nil
        self.addSubview(captionView)
        
        postImage = UIImageView(frame: CGRect(x: 14, y: 36, width: 71, height: 99))
        postImage.image = post.postImage.first ?? UIImage(color: UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0))
        postImage.clipsToBounds = true
        postImage.layer.cornerRadius = 3.33
        postImage.contentMode = .scaleAspectFill
        captionView.addSubview(postImage)
        
        
        postCaption = VerticallyCenteredTextView(frame: CGRect(x: postImage.frame.maxX + 9, y: 10, width: 219, height: 160))
        postCaption.textColor = UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
        
        if post.caption == "" {
            postCaption.alpha = 0.5
            postCaption.text = "Write a caption..."
        } else {
            postCaption.text = post.caption
        }
        
        postCaption.font = UIFont(name: "SFCamera-Regular", size: 13)
        postCaption.backgroundColor = nil
        postCaption.isScrollEnabled = true
        postCaption.textContainer.lineBreakMode = .byTruncatingHead
        postCaption.keyboardDistanceFromTextField = 100
        postCaption.delegate = self
        captionView.addSubview(postCaption)
        
        //postCaption.frame = CGRect(x: postCaption.frame.minX, y: (183 - postCaption.frame.height)/2, width: 219, height: postCaption.frame.height)
        
        let bottomLine = UIView(frame: CGRect(x: 0, y: 182, width: self.bounds.width, height: 1))
        bottomLine.backgroundColor = UIColor(red: 0.179, green: 0.179, blue: 0.179, alpha: 1)
        captionView.addSubview(bottomLine)
        
        locationView = UIView(frame: CGRect(x: 0, y: captionView.frame.maxY, width: self.bounds.width, height: 56))
        locationView.backgroundColor = nil
        self.addSubview(locationView)
        
        let postLabel = UILabel(frame: CGRect(x: 14, y: 10, width: 100, height: 17))
        postLabel.text = "Post location"
        postLabel.textColor = UIColor(red: 0.706, green: 0.706, blue: 0.706, alpha: 1)
        postLabel.font = UIFont(name: "SFCamera-Regular", size: 12.5)
        locationView.addSubview(postLabel)
        
        addressButton = UIButton(frame: CGRect(x: 14, y: postLabel.frame.maxY - 4, width: self.bounds.width - 50, height: 15))
        addressButton.setTitleColor(UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1), for: .normal)
        addressButton.titleLabel?.font = UIFont(name: "SFCamera-Semibold", size: 11.5)
        addressButton.titleLabel?.lineBreakMode = .byTruncatingTail
        addressButton.addTarget(self, action: #selector(editAddress(_:)), for: .touchUpInside)
        
        postVC.reverseGeocodeFromCoordinate(numberOfFields: 4, location: CLLocation(latitude: post.postLat, longitude: post.postLong)) { [weak self] (address) in
            guard let self = self else { return }
            
            self.addressButton.setTitle(address, for: .normal)
            self.addressButton.sizeToFit()
            self.locationView.addSubview(self.addressButton)
            
            self.editAddress = UIButton(frame: CGRect(x: self.addressButton.frame.maxX + 2, y: postLabel.frame.maxY - 5, width: 27, height: 27))
            self.editAddress.setImage(UIImage(named: "EditPost"), for: .normal)
            self.editAddress.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
            self.editAddress.addTarget(self, action: #selector(self.editAddress(_:)), for: .touchUpInside)
            self.locationView.addSubview(self.editAddress)
        }
        
        let line = UIView(frame: CGRect(x: 0, y: 55, width: self.bounds.width, height: 1))
        line.backgroundColor = UIColor(red: 0.179, green: 0.179, blue: 0.179, alpha: 1)
        locationView.addSubview(line)
        
        privacyView = UIView(frame: CGRect(x: 0, y: locationView.frame.maxY, width: self.bounds.width, height: 106))
        privacyView.backgroundColor = nil
        self.addSubview(privacyView)
        
        whoCanSee = UILabel(frame: CGRect(x: 14, y: 10, width: 100, height: 17))
        whoCanSee.text = "Who can see?"
        whoCanSee.textColor = UIColor(red: 0.706, green: 0.706, blue: 0.706, alpha: 1)
        whoCanSee.font = UIFont(name: "SFCamera-Regular", size: 12.5)
        privacyView.addSubview(whoCanSee)
        
        privacyIcon = UIImageView()
        privacyIcon.contentMode = .scaleAspectFit
        
        privacyLabel = UILabel()
        privacyLabel.textColor = .white
        privacyLabel.font = UIFont(name: "SFCamera-Semibold", size: 13)
        
        friendCount = UILabel()
        friendCount.textColor = UIColor(named: "SpotGreen")
        friendCount.font = UIFont(name: "SFCamera-Regular", size: 10.5)
        
        actionArrow = UIButton()
        actionArrow.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        actionArrow.setImage(UIImage(named: "ActionArrow"), for: .normal)
        actionArrow.addTarget(self, action: #selector(actionTap(_:)), for: .touchUpInside)
        
        loadPrivacyView()
        privacyView.addSubview(privacyIcon)
        privacyView.addSubview(privacyLabel)
        
        if post.privacyLevel == "invite" { privacyView.addSubview(friendCount) }
        if  !(post.isFirst ?? true) && (post.spotID == "" || post.spotPrivacy != "invite") { privacyView.addSubview(actionArrow) }
        
        let cancelButton = UIButton(frame: CGRect(x: 200, y: 70, width: 65, height: 20))
        cancelButton.titleEdgeInsets = UIEdgeInsets(top: 2.5, left: 2.5, bottom: 2.5, right: 2.5)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(UIColor(red: 0.769, green: 0.769, blue: 0.769, alpha: 1), for: .normal)
        cancelButton.titleLabel?.font = UIFont(name: "SFCamera-Regular", size: 14)
        cancelButton.addTarget(self, action: #selector(cancelTap(_:)), for: .touchUpInside)
        privacyView.addSubview(cancelButton)
        
        let saveButton = UIButton(frame: CGRect(x: 275, y: 70, width: 43, height: 20))
        saveButton.titleEdgeInsets = UIEdgeInsets(top: 2.5, left: 2.5, bottom: 2.5, right: 2.5)
        saveButton.setTitle("Save", for: .normal)
        saveButton.setTitleColor(UIColor(named: "SpotGreen"), for: .normal)
        saveButton.titleLabel?.font = UIFont(name: "SFCamera-Semibold", size: 14)
        saveButton.addTarget(self, action: #selector(saveTap(_:)), for: .touchUpInside)
        privacyView.addSubview(saveButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func loadPrivacyView() {
        let privacyString = post.privacyLevel!.prefix(1).capitalized + post.privacyLevel!.dropFirst()
        privacyLabel.text = privacyString
        
        if post.privacyLevel == "friends" {
            privacyIcon.frame = CGRect(x: 14, y: whoCanSee.frame.maxY + 10, width: 20, height: 13)
            privacyIcon.image = UIImage(named: "FriendsIcon")
            privacyLabel.frame = CGRect(x: privacyIcon.frame.maxX + 6, y: privacyIcon.frame.minY - 2, width: 100, height: 15)
        } else if post.privacyLevel == "public" {
            privacyIcon.frame = CGRect(x: 14, y: whoCanSee.frame.maxY + 10, width: 18, height: 18)
            privacyIcon.image = UIImage(named: "PublicIcon")
            privacyLabel.frame = CGRect(x: privacyIcon.frame.maxX + 6, y: privacyIcon.frame.minY + 1, width: 100, height: 15)
        } else {
            privacyIcon.frame = CGRect(x: 14, y: whoCanSee.frame.maxY + 11, width: 17.8, height: 22.25)
            privacyIcon.image = UIImage(named: "PrivateIcon")
            privacyLabel.frame = CGRect(x: privacyIcon.frame.maxX + 8, y: privacyIcon.frame.minY + 5, width: 100, height: 15)
            privacyLabel.text = "Private"
        }
        
        privacyLabel.sizeToFit()
        
        if post.privacyLevel == "invite" {
            privacyLabel.frame = CGRect(x: privacyIcon.frame.maxX + 8, y: whoCanSee.frame.maxY + 6.5, width: 100, height: 15)
            privacyLabel.sizeToFit()
            
            friendCount.frame = CGRect(x: privacyIcon.frame.maxX + 8, y: privacyLabel.frame.maxY + 2, width: 70, height: 14)
            var countText = "\(post.inviteList?.count ?? 0) friend"
            if post.inviteList?.count != 1 { countText += "s"}
            friendCount.text = countText
            friendCount.sizeToFit()
        }
        
        if  !(post.isFirst ?? true) && (post.spotID == "" || post.spotPrivacy != "invite") {
            actionArrow.frame = CGRect(x: privacyLabel.frame.maxX, y: privacyLabel.frame.minY, width: 23, height: 17)
        }
    }
    
    @objc func editSpotTap(_ sender: UIButton) {
        removeEditPost()
        postVC.editPostView = false
        postVC.openSpotPage(edit: true)
    }
    
    @objc func editAddress(_ sender: UIButton) {
        if let vc = UIStoryboard(name: "AddSpot", bundle: nil).instantiateViewController(identifier: "LocationPicker") as? LocationPickerController {
            
            vc.selectedImages = post.postImage
            vc.mapVC = postVC.mapVC
            vc.passedLocation = CLLocation(latitude: post.postLat, longitude: post.postLong)
            if post.spotID != "" {
                vc.secondaryLocation = CLLocation(latitude: post.spotLat ?? post.postLong, longitude: post.spotLong ?? post.postLong)
                vc.spotName = post.spotName ?? ""
            }
            
            vc.passedAddress = addressButton.titleLabel?.text ?? ""
            postVC.mapVC.navigationController?.pushViewController(vc, animated: false)
            
            removeEditPost()
        }
    }
    
    @objc func actionTap(_ sender: UIButton) {
        ///show privacy picker on action arrow tap
        if let postMask = self.superview {
            privacyMask = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
            privacyMask.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            privacyMask.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closePrivacyPicker(_:))))
            postMask.addSubview(privacyMask)
            
            let pickerView = UIView(frame: CGRect(x: 0, y: UIScreen.main.bounds.height - 260, width: UIScreen.main.bounds.width, height: 260))
            pickerView.backgroundColor = UIColor(named: "SpotBlack")
            privacyMask.addSubview(pickerView)
            
            let titleLabel = UILabel(frame: CGRect(x: UIScreen.main.bounds.width/2 - 100, y: 10, width: 200, height: 20))
            titleLabel.text = "Who can see this?"
            titleLabel.textColor = UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
            titleLabel.font = UIFont(name: "SFCamera-Semibold", size: 15)
            titleLabel.textAlignment = .center
            pickerView.addSubview(titleLabel)
            
            let publicButton = UIButton(frame: CGRect(x: 14, y: 50, width: 171, height: 54))
            publicButton.setImage(UIImage(named: "PublicButton"), for: .normal)
            publicButton.layer.cornerRadius = 7.5
            publicButton.tag = 0
            publicButton.addTarget(self, action: #selector(privacyTap(_:)), for: .touchUpInside)
            if post.privacyLevel == "public" {
                publicButton.layer.borderWidth = 1
                publicButton.layer.borderColor = UIColor(named: "SpotGreen")?.cgColor
            }
            pickerView.addSubview(publicButton)
            
            let friendsButton = UIButton(frame: CGRect(x: 14, y: publicButton.frame.maxY + 10, width: 171, height: 54))
            friendsButton.setImage(UIImage(named: "FriendsButton"), for: .normal)
            friendsButton.layer.cornerRadius = 7.5
            friendsButton.tag = 1
            friendsButton.addTarget(self, action: #selector(privacyTap(_:)), for: .touchUpInside)
            if post.privacyLevel == "friends" {
                friendsButton.layer.borderWidth = 1
                friendsButton.layer.borderColor = UIColor(named: "SpotGreen")?.cgColor
            }
            pickerView.addSubview(friendsButton)
        }
    }
    
    @objc func privacyTap(_ sender: UIButton) {
        
        switch sender.tag {
        case 0:
            post.privacyLevel = "public"
            postVC.editedPost.privacyLevel = "public"
        default:
            post.privacyLevel = "friends"
            postVC.editedPost.privacyLevel = "friends"
        }
        
        for subview in privacyMask.subviews { subview.removeFromSuperview() }
        privacyMask.removeFromSuperview()
        
        loadPrivacyView()
    }
    
    
    @objc func closePrivacyPicker(_ sender: UITapGestureRecognizer) {
        for subview in privacyMask.subviews { subview.removeFromSuperview() }
        privacyMask.removeFromSuperview()
    }
    
    @objc func cancelTap(_ sender: UIButton) {
        removeEditPost()
        postVC.editPostView = false
    }
    
    func removeEditPost() {
            
        postVC.editPostView = false
        postVC.mapVC.removeTable()
        postVC.tableView.reloadData()
        
        if let postMask = self.superview {
            postMask.removeFromSuperview()
        }
        
        for sub in self.subviews {
            sub.removeFromSuperview()
        }
        
        self.removeFromSuperview()
    }
    
    @objc func saveTap(_ sender: UIButton) {
        
        Mixpanel.mainInstance().track(event: "EditPostSave")
        
        let captionText = postCaption.text == "Write a caption..." ? "" : postCaption.text
        
        var taggedUsernames: [String] = []
        var selectedUsers: [UserProfile] = []
        
        ///for tagging users on comment post
        let word = captionText!.split(separator: " ")
        
        for w in word {
            let username = String(w.dropFirst())
            if w.hasPrefix("@") {
                if let f = postVC.mapVC.friendsList.first(where: {$0.username == username}) {
                    selectedUsers.append(f)
                }
            }
        }
        
        taggedUsernames = selectedUsers.map({$0.username})
        
        postVC.postsList[postVC.selectedPostIndex].caption = captionText ?? ""
        postVC.postsList[postVC.selectedPostIndex].taggedUsers = taggedUsernames
        postVC.postsList[postVC.selectedPostIndex].postLong = postVC.editedPost.postLong
        postVC.postsList[postVC.selectedPostIndex].postLat = postVC.editedPost.postLat
        postVC.postsList[postVC.selectedPostIndex].privacyLevel = postVC.editedPost.privacyLevel
        
        let uploadPost = postVC.postsList[postVC.selectedPostIndex]
        
        postVC.editedPost = nil
        postVC.editPostView = false
        postVC.tableView.reloadData()
        removeEditPost()
        
        //reset annotation
        postVC.mapVC.postsList = postVC.postsList
        let mapPass = ["selectedPost": postVC.selectedPostIndex as Any, "firstOpen": false, "parentVC": postVC.parentVC] as [String : Any]
        NotificationCenter.default.post(name: Notification.Name("PostOpen"), object: nil, userInfo: mapPass)
        
        let infoPass: [String: Any] = ["post": uploadPost as Any]
        NotificationCenter.default.post(name: Notification.Name("EditPost"), object: nil, userInfo: infoPass)
        
        let values : [String: Any] = ["caption" : captionText ?? "", "postLat": uploadPost.postLat, "postLong": uploadPost.postLong, "privacyLevel": uploadPost.privacyLevel as Any, "taggedUsers": taggedUsernames]
        updatePostValues(values: values)
        
        /// update city on location change
        let db = Firestore.firestore()
        postVC.reverseGeocodeFromCoordinate(numberOfFields: 2, location: CLLocation(latitude: uploadPost.postLat, longitude: uploadPost.postLong)) { (city) in

            if city == "" { return }
            db.collection("posts").document(uploadPost.id!).updateData(["city" : city])
        }
    }
    
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.alpha == 0.5 {
            textView.text = nil
            textView.alpha = 1.0
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.alpha = 0.5
            textView.text = "Write a caption..."
        }
    }
    
    func textViewDidChange(_ textView: UITextView) {
        if textView.text.last != " " {
            if let word = textView.text?.split(separator: " ").last {
                if word.hasPrefix("@") {
                    self.postVC.mapVC.addTable(text: String(word.lowercased().dropFirst()), parent: .post)
                    return
                }
            }
        }
        
        postVC.mapVC.removeTable()
    }
    
    
    func updatePostValues(values: [String: Any]) {
        let db = Firestore.firestore()
        db.collection("posts").document(post.id!).updateData(values)
        
        let pQuery = db.collection("posts").document(post.id!).collection("comments").order(by: "timestamp", descending: false)
        
        pQuery.getDocuments { (postSnap, err) in
            if err == nil {
                if let doc = postSnap?.documents.first {
                    db.collection("posts").document(self.post.id!).collection("comments").document(doc.documentID).updateData(["comment": values["caption"] as Any])
                }
            }
        }
        
        if post.spotID != "" && post.spotID != nil {
            db.collection("spots").document(post.spotID!).collection("feedPost").document(post.id!).updateData(values)
            let sQuery = db.collection("spots").document(post.spotID!).collection("feedPost").document(post.id!).collection("Comments").order(by: "timestamp", descending: false)
            sQuery.getDocuments { (spotSnap, err) in
                if err == nil {
                    if let doc = spotSnap?.documents.first {
                        db.collection("spots").document(self.post.spotID!).collection("feedPost").document(self.post.id!).collection("Comments").document(doc.documentID).updateData(["comment": values["caption"] as Any])
                    }
                }
            }
        }
    }
}

class VerticallyCenteredTextView: UITextView {
    override var contentSize: CGSize {
        didSet {
            var topCorrection = (bounds.size.height - contentSize.height * zoomScale) / 2.0
            topCorrection = max(0, topCorrection)
            contentInset = UIEdgeInsets(top: topCorrection, left: 0, bottom: 0, right: 0)
        }
    }
}
///https://stackoverflow.com/questions/12591192/center-text-vertically-in-a-uitextview

extension UILabel {
    
    func addTrailing(with trailingText: String, moreText: String, moreTextFont: UIFont, moreTextColor: UIColor) {
        
        let readMoreText: String = trailingText + moreText
        
        if self.visibleTextLength == 0 { return }
        
        let lengthForVisibleString: Int = self.visibleTextLength
        
        if let myText = self.text {
            
            let mutableString: String = myText
            
            let trimmedString: String? = (mutableString as NSString).replacingCharacters(in: NSRange(location: lengthForVisibleString, length: myText.count - lengthForVisibleString), with: "")
            
            let readMoreLength: Int = (readMoreText.count)
            
            guard let safeTrimmedString = trimmedString else { return }
            
            if safeTrimmedString.count <= readMoreLength { return }
            
            // "safeTrimmedString.count - readMoreLength" should never be less then the readMoreLength because it'll be a negative value and will crash
            let trimmedForReadMore: String = (safeTrimmedString as NSString).replacingCharacters(in: NSRange(location: safeTrimmedString.count - readMoreLength, length: readMoreLength), with: "") + trailingText
            
            let answerAttributed = NSMutableAttributedString(string: trimmedForReadMore, attributes: [NSAttributedString.Key.font: self.font as Any])
            let readMoreAttributed = NSMutableAttributedString(string: moreText, attributes: [NSAttributedString.Key.font: moreTextFont, NSAttributedString.Key.foregroundColor: moreTextColor])
            answerAttributed.append(readMoreAttributed)
            self.attributedText = answerAttributed
        }
    }
    
    var visibleTextLength: Int {
        
        let font: UIFont = self.font
        let mode: NSLineBreakMode = self.lineBreakMode
        let labelWidth: CGFloat = self.frame.size.width
        let labelHeight: CGFloat = self.frame.size.height
        let sizeConstraint = CGSize(width: labelWidth, height: CGFloat.greatestFiniteMagnitude)
        
        if let myText = self.text {
            
            let attributes: [AnyHashable: Any] = [NSAttributedString.Key.font: font]
            let attributedText = NSAttributedString(string: myText, attributes: attributes as? [NSAttributedString.Key : Any])
            let boundingRect: CGRect = attributedText.boundingRect(with: sizeConstraint, options: .usesLineFragmentOrigin, context: nil)
            
            if boundingRect.size.height > labelHeight {
                var index: Int = 0
                var prev: Int = 0
                let characterSet = CharacterSet.whitespacesAndNewlines
                repeat {
                    prev = index
                    if mode == NSLineBreakMode.byCharWrapping {
                        index += 1
                    } else {
                        index = (myText as NSString).rangeOfCharacter(from: characterSet, options: [], range: NSRange(location: index + 1, length: myText.count - index - 1)).location
                    }
                } while index != NSNotFound && index < myText.count && (myText as NSString).substring(to: index).boundingRect(with: sizeConstraint, options: .usesLineFragmentOrigin, attributes: attributes as? [NSAttributedString.Key : Any], context: nil).size.height <= labelHeight
                return prev
            }
        }
        
        if self.text == nil {
            return 0
        } else {
            return self.text!.count
        }
    }
}
///https://stackoverflow.com/questions/32309247/add-read-more-to-the-end-of-uilabel

extension UIImageView {
    
    func addTopMask() {
        let topMask = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 72))
        topMask.backgroundColor = nil
        let layer0 = CAGradientLayer()
        layer0.frame = topMask.bounds
        layer0.colors = [
            UIColor(red: 0, green: 0, blue: 0, alpha: 0).cgColor,
            UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 0.32).cgColor,
            UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 0.6).cgColor
        ]
        layer0.locations = [0, 0.49, 1.0]
        layer0.startPoint = CGPoint(x: 0.5, y: 1.0)
        layer0.endPoint = CGPoint(x: 0.5, y: 0)
        topMask.layer.addSublayer(layer0)
        self.addSubview(topMask)
    }
}

class PostImageLoader: Operation {
    var images: [UIImage] = []
    var loadingCompleteHandler: (([UIImage]?) -> ())?
    private var post: MapPost
    
    init(_ post: MapPost) {
        self.post = post
    }
    
    override func main() {
        if isCancelled { return }
        
        var imageCount = 0
        var images: [UIImage] = []
        for _ in post.imageURLs {
            images.append(UIImage())
        }
        
        func imageEscape() {
            
            imageCount += 1
            if imageCount == post.imageURLs.count {
                self.images = images
                self.loadingCompleteHandler?(images)
            }
        }

        for postURL in post.imageURLs {
            SDWebImageManager.shared.loadImage(with: URL(string: postURL), options: .highPriority, context: .none, progress: nil) { (image, data, err, cache, download, url) in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.isCancelled { return }
                    
                    let i = self.post.imageURLs.lastIndex(where: {$0 == postURL})
                    images[i ?? 0] = image ?? UIImage()
                    imageEscape()
                }
            }
        }
    }
}

