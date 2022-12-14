//
//  MapController.swift
//  Spot
//
//  Created by kbarone on 2/15/19.
//   Copyright © 2019 sp0t, LLC. All rights reserved.
//
import Firebase
import GeoFire
import Geofirestore
import MapKit
import Mixpanel
import UIKit

protocol MapControllerDelegate: AnyObject {
    func displayHeelsMap()
}

final class MapController: UIViewController {
    let db = Firestore.firestore()
    let uid: String = Auth.auth().currentUser?.uid ?? "invalid user"
    
    lazy var mapPostService: MapPostServiceProtocol? = {
        let service = try? ServiceContainer.shared.service(for: \.mapPostService)
        return service
    }()

    lazy var spotService: SpotServiceProtocol? = {
        let service = try? ServiceContainer.shared.service(for: \.spotService)
        return service
    }()

    let locationManager = CLLocationManager()
    var friendsPostsListener, mapsListener, mapsPostsListener, notiListener, userListener: ListenerRegistration?
    let homeFetchGroup = DispatchGroup()
    let chapelHillLocation = CLLocation(latitude: 35.913_2, longitude: -79.055_8)

    var geoQueryLimit: Int = 50

    var selectedItemIndex = 0
    var firstOpen = false
    var firstTimeGettingLocation = true
    var openedExploreMaps = false
    var userLoaded = false
    var postsFetched = false
    var mapsLoaded = false
    var friendsLoaded = false
    var homeFetchLeaveCount = 0

    lazy var friendsPostsDictionary = [String: MapPost]()
    lazy var postGroup: [MapPostGroup] = []
    lazy var mapFetchIDs: [String] = [] // used to track for deleted posts

    var refresh: RefreshStatus = .activelyRefreshing
    var friendsRefresh: RefreshStatus = .refreshEnabled

    var newMapID: String?

    lazy var addFriendsView: AddFriendsView = {
        let view = AddFriendsView()
        view.layer.cornerRadius = 13
        view.isHidden = false
        return view
    }()

    var titleView: MapTitleView?
    lazy var mapView = SpotMapView()
    lazy var cityLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont(name: "UniversCE-Black", size: 13)
        label.textAlignment = .center
        return label
    }()

    lazy var newPostsButton = NewPostsButton()
    lazy var mapsCollection: UICollectionView = {
        let layout = UICollectionViewFlowLayout {
            $0.minimumInteritemSpacing = 5
            $0.scrollDirection = .horizontal
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .white
        view.showsHorizontalScrollIndicator = false
        view.clipsToBounds = false
        view.contentInset = UIEdgeInsets(top: 5, left: 9, bottom: 0, right: 9)
        view.register(MapLoadingCell.self, forCellWithReuseIdentifier: "MapLoadingCell")
        view.register(FriendsMapCell.self, forCellWithReuseIdentifier: "FriendsCell")
        view.register(MapHomeCell.self, forCellWithReuseIdentifier: "MapCell")
        view.register(AddMapCell.self, forCellWithReuseIdentifier: "AddMapCell")
        view.register(CampusMapCell.self, forCellWithReuseIdentifier: "CampusMapCell")
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "Default")
        return view
    }()

    var sheetView: DrawerView? {
        didSet {
            let hidden = sheetView != nil
            DispatchQueue.main.async {
                self.toggleHomeAppearance(hidden: hidden)
                if !hidden { self.animateHomeAlphas() }
                self.navigationController?.setNavigationBarHidden(hidden, animated: false)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViews()
        checkLocationAuth()
        getAdmins() /// get admin users to exclude from analytics
        addNotifications()
        runMapFetches()
        setUpNavBar()
        locationManager.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Mixpanel.mainInstance().track(event: "MapOpen")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .darkContent
    }

    func addNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(notifyUserLoad(_:)), name: NSNotification.Name(("UserProfileLoad")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyPostOpen(_:)), name: NSNotification.Name(("PostOpen")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyCommentChange(_:)), name: NSNotification.Name(("CommentChange")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyPostDelete(_:)), name: NSNotification.Name(("DeletePost")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyNewPost(_:)), name: NSNotification.Name(("NewPost")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyEditMap(_:)), name: NSNotification.Name(("EditMap")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyLogout), name: NSNotification.Name(("Logout")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notifyFriendRemove), name: NSNotification.Name(("FriendRemove")), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    func setUpViews() {
        addMapView()
        addMapsCollection()
        addSupplementalViews()
    }

    func addMapView() {
        mapView.delegate = self
        mapView.spotMapDelegate = self
        view.addSubview(mapView)
        makeMapHomeConstraints()
    }

    func makeMapHomeConstraints() {
        mapView.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
         //   $0.top.equalTo(mapsCollection.snp.bottom)
            $0.bottom.equalToSuperview().offset(65)
        }
    }

    func addMapsCollection() {
        mapsCollection.delegate = self
        mapsCollection.dataSource = self
        view.addSubview(mapsCollection)
        mapsCollection.snp.makeConstraints {
            $0.top.equalTo(view.safeAreaLayoutGuide.snp.topMargin)
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(114)
        }
        mapsCollection.layoutIfNeeded()
        mapsCollection.addShadow(shadowColor: UIColor(red: 0, green: 0, blue: 0, alpha: 0.1).cgColor, opacity: 1, radius: 12, offset: CGSize(width: 0, height: 1))
    }

    func addSupplementalViews() {
        view.addSubview(cityLabel)
        cityLabel.snp.makeConstraints {
            $0.top.equalTo(mapsCollection.snp.bottom).offset(6)
            $0.centerX.equalToSuperview()
        }

        let addButton = AddButton {
            $0.addTarget(self, action: #selector(addTap(_:)), for: .touchUpInside)
            mapView.addSubview($0)
        }
        addButton.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(23)
            $0.bottom.equalToSuperview().inset(100) /// offset 65 px for portion of map below fold
            $0.height.width.equalTo(109)
        }

        newPostsButton.isHidden = true
        view.addSubview(newPostsButton)
        newPostsButton.snp.makeConstraints {
            $0.bottom.equalTo(addButton.snp.top).offset(-1)
            $0.trailing.equalTo(-21)
            $0.height.equalTo(68)
            $0.width.equalTo(66)
        }
    }

    func setUpNavBar() {
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = nil

        view.backgroundColor = .white
        navigationController?.navigationBar.addWhiteBackground()
        navigationItem.titleView = getTitleView()
        if let mapNav = navigationController as? MapNavigationController {
            mapNav.requiredStatusBarStyle = .darkContent
        }
    }

    func getTitleView() -> UIView {
        if let titleView { return titleView }

        titleView = MapTitleView {
            $0.searchButton.addTarget(self, action: #selector(searchTap(_:)), for: .touchUpInside)
            $0.profileButton.addTarget(self, action: #selector(profileTap(_:)), for: .touchUpInside)
            $0.notificationsButton.addTarget(self, action: #selector(openNotis(_:)), for: .touchUpInside)
        }

        let notificationRef = self.db.collection("users").document(self.uid).collection("notifications")
        let query = notificationRef.whereField("seen", isEqualTo: false)

        /// show green bell on notifications when theres an unseen noti
        if notiListener != nil { notiListener?.remove() }
        print("add noti listener")
        notiListener = query.addSnapshotListener(includeMetadataChanges: true) { (snap, err) in
            if err != nil || snap?.metadata.isFromCache ?? false {
                return
            } else {
                if !(snap?.documents.isEmpty ?? true) {
                    self.titleView?.notificationsButton.pendingCount = snap?.documents.count ?? 0
                } else {
                    self.titleView?.notificationsButton.pendingCount = 0
                }
            }
        }

        return titleView ?? UIView()
    }

    func openNewMap() {
        Mixpanel.mainInstance().track(event: "MapControllerNewMapTap")
        if navigationController?.viewControllers.contains(where: { $0 is NewMapController }) ?? false {
            return
        }

        DispatchQueue.main.async { [weak self] in
            if let vc = UIStoryboard(name: "Upload", bundle: nil).instantiateViewController(withIdentifier: "NewMap") as? NewMapController {
                UploadPostModel.shared.createSharedInstance()
                vc.presentedModally = true
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

    @objc func addTap(_ sender: UIButton) {
        Mixpanel.mainInstance().track(event: "MapControllerAddTap")
        addFriendsView.removeFromSuperview()

        /// crash on double stack was happening here
        if navigationController?.viewControllers.contains(where: { $0 is AVCameraController }) ?? false {
            return
        }

        guard let vc = UIStoryboard(name: "Upload", bundle: nil).instantiateViewController(identifier: "AVCameraController") as? AVCameraController
        else { return }

        let transition = AddButtonTransition()
        self.navigationController?.view.layer.add(transition, forKey: kCATransition)
        self.navigationController?.pushViewController(vc, animated: false)
    }

    @objc func profileTap(_ sender: Any) {
        if sheetView != nil { return } /// cancel on double tap
        Mixpanel.mainInstance().track(event: "MapControllerProfileTap")
        let profileVC = ProfileViewController(userProfile: nil)

        sheetView = DrawerView(present: profileVC, detentsInAscending: [.bottom, .middle, .top], closeAction: { [weak self] in
            self?.sheetView = nil
        })
        profileVC.containerDrawerView = sheetView
        sheetView?.present(to: .top)
    }

    @objc func openNotis(_ sender: UIButton) {
        if sheetView != nil { return } /// cancel on double tap
        Mixpanel.mainInstance().track(event: "MapControllerNotificationsTap")
        let notifVC = NotificationsController()
        sheetView = DrawerView(present: notifVC, detentsInAscending: [.bottom, .middle, .top], closeAction: { [weak self] in
            self?.sheetView = nil
        })
        notifVC.containerDrawerView = sheetView
        sheetView?.present(to: .top)
    }

    @objc func searchTap(_ sender: UIButton) {
        Mixpanel.mainInstance().track(event: "MapControllerSearchTap")
        openFindFriends()
    }

    @objc func findFriendsTap(_ sender: UIButton) {
        Mixpanel.mainInstance().track(event: "MapControllerFindFriendsTap")
        openFindFriends()
    }

    func openFindFriends() {
        if sheetView != nil { return } // cancel on double tap
        let ffvc = FindFriendsController()
        sheetView = DrawerView(present: ffvc, detentsInAscending: [.top, .middle, .bottom]) { [weak self] in
            self?.sheetView = nil
        }
        ffvc.containerDrawerView = sheetView
    }

    func openPost(posts: [MapPost]) {
        if sheetView != nil { return } /// cancel on double tap
        guard let postVC = UIStoryboard(name: "Feed", bundle: nil).instantiateViewController(identifier: "Post") as? PostController else { return }
        postVC.postsList = posts
        sheetView = DrawerView(present: postVC, detentsInAscending: [.bottom, .middle, .top]) { [weak self] in
            self?.sheetView = nil
        }
        postVC.containerDrawerView = sheetView
        sheetView?.present(to: .top)
    }

    func openSelectedMap() {
        if sheetView != nil { return } /// cancel on double tap
        var map = getSelectedMap()
        let unsortedPosts = map == nil ? friendsPostsDictionary.map { $0.value } : map?.postsDictionary.map { $0.value } ?? []
        let posts = mapView.sortPosts(unsortedPosts)
        let mapType: MapType = map == nil ? .friendsMap : .customMap
        /// create map from current posts for friends map
        if map == nil { map = getFriendsMapObject() }

        let customMapVC = CustomMapController(userProfile: nil, mapData: map, postsList: posts, presentedDrawerView: nil, mapType: mapType)

        sheetView = DrawerView(present: customMapVC, detentsInAscending: [.bottom, .middle, .top]) { [weak self] in
            self?.sheetView = nil
        }

        customMapVC.containerDrawerView = sheetView
        sheetView?.present(to: .top)
    }

    func openSpot(spotID: String, spotName: String, mapID: String, mapName: String) {
        /// cancel on double tap
        if sheetView != nil {
            return
        }

        let emptyPost = MapPost(spotID: spotID, spotName: spotName, mapID: mapID, mapName: mapName)

        let spotVC = SpotPageController(mapPost: emptyPost, presentedDrawerView: nil)
        sheetView = DrawerView(present: spotVC, detentsInAscending: [.bottom, .middle, .top]) { [weak self] in
            self?.sheetView = nil
        }

        spotVC.containerDrawerView = sheetView
        sheetView?.present(to: .top)
    }

    func openExploreMaps(onboarding: Bool) {
        let fromValue: ExploreMapViewModel.OpenedFrom = onboarding ? .onBoarding : .mapController
        let viewController = ExploreMapViewController(viewModel: ExploreMapViewModel(serviceContainer: ServiceContainer.shared, from: fromValue))
        let transition = AddButtonTransition()
        self.navigationController?.view.layer.add(transition, forKey: kCATransition)
        self.navigationController?.pushViewController(viewController, animated: false)
    }

    func toggleHomeAppearance(hidden: Bool) {
        mapsCollection.isHidden = hidden
        newPostsButton.setHidden(hidden: hidden)
        cityLabel.isHidden = hidden
        /// if hidden, remove annotations, else reset with selected annotations
        if hidden {
            addFriendsView.removeFromSuperview()
        } else {
            mapView.delegate = self
            mapView.spotMapDelegate = self
            DispatchQueue.main.async { self.addMapAnnotations(index: self.selectedItemIndex, reload: true) }
        }
    }

    func animateHomeAlphas() {
        navigationController?.navigationBar.alpha = 0.0
        mapsCollection.alpha = 0.0
        newPostsButton.alpha = 0.0
        cityLabel.alpha = 0.0

        UIView.animate(withDuration: 0.15) {
            self.navigationController?.navigationBar.alpha = 1
            self.mapsCollection.alpha = 1
            self.newPostsButton.alpha = 1
            self.cityLabel.alpha = 1
        }
    }

    /// custom reset nav bar (patch fix for CATransition)
    func uploadMapReset() {
        DispatchQueue.main.async { self.setUpNavBar() }
    }
}

extension MapController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            Mixpanel.mainInstance().track(event: "LocationServicesDenied")
        } else if status == .authorizedWhenInUse || status == .authorizedWhenInUse {
            Mixpanel.mainInstance().track(event: "LocationServicesAllowed")
            UploadPostModel.shared.locationAccess = true
            locationManager.startUpdatingLocation()
        }
        // ask for notifications access immediately after location access
        let pushManager = PushNotificationManager(userID: uid)
        pushManager.registerForPushNotifications()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        UserDataModel.shared.currentLocation = location
        if firstTimeGettingLocation {
            if manager.accuracyAuthorization == .reducedAccuracy { Mixpanel.mainInstance().track(event: "PreciseLocationOff") }
            /// set current location to show while feed loads
            firstTimeGettingLocation = false
            NotificationCenter.default.post(name: Notification.Name("UpdateLocation"), object: nil)

            /// map might load before user accepts location services
            if self.mapsLoaded {
                self.displayHeelsMap()
            } else {
                self.mapView.setRegion(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 400_000, longitudinalMeters: 400_000), animated: false)
            }
        }
    }

    func checkLocationAuth() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // prompt user to open their settings if they havent allowed location services

        case .restricted, .denied:
            presentLocationAlert()

        case .authorizedWhenInUse, .authorizedAlways:
            UploadPostModel.shared.locationAccess = true
            locationManager.startUpdatingLocation()

        @unknown default:
            return
        }
    }

    func presentLocationAlert() {
        let alert = UIAlertController(
            title: "Spot needs your location to find spots near you",
            message: nil,
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(title: "Settings", style: .default) { _ in
                Mixpanel.mainInstance().track(event: "LocationServicesSettingsOpen")
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        )

        alert.addAction(
            UIAlertAction(title: "Cancel", style: .cancel) { _ in
            }
        )

        self.present(alert, animated: true, completion: nil)
    }
}

extension MapController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      /*  if otherGestureRecognizer.view?.tag == 16 || otherGestureRecognizer.view?.tag == 23 || otherGestureRecognizer.view?.tag == 30 {
            return false
        } */
        return true
    }
}
