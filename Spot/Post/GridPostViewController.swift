//
//  GridPostViewController.swift
//  Spot
//
//  Created by Kenny Barone on 3/16/23.
//  Copyright © 2023 sp0t, LLC. All rights reserved.
//

import UIKit
import Mixpanel
import IdentifiedCollections

protocol PostControllerDelegate: AnyObject {
    func indexChanged(rowsRemaining: Int)
}

final class GridPostViewController: UIViewController {
    var parentVC: PostParent
    private var postsList: IdentifiedArrayOf<MapPost> = []
    weak var delegate: PostControllerDelegate?
    var openComments = false
    
    private var selectedPostIndex: Int = 0 {
        didSet {
            delegate?.indexChanged(rowsRemaining: postsList.count - selectedPostIndex)
        }
    }

    private lazy var postService: MapPostServiceProtocol? = {
        let service = try? ServiceContainer.shared.service(for: \.mapPostService)
        return service
    }()

<<<<<<< HEAD
    lazy var mapService: MapServiceProtocol? = {
        let service = try? ServiceContainer.shared.service(for: \.mapsService)
        return service
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInsetReference = .fromContentInset
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.isScrollEnabled = true
        collectionView.isPagingEnabled = true
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false

        collectionView.register(MapPostImageCell.self, forCellWithReuseIdentifier: MapPostImageCell.reuseID)
        collectionView.register(MapPostVideoCell.self, forCellWithReuseIdentifier: MapPostVideoCell.reuseID)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        return collectionView
    }()

    var titleView: GridPostTitleView
    private lazy var addMapConfirmationView = AddMapConfirmationView()
    var mapData: CustomMap?

    init(parentVC: PostParent, postsList: [MapPost], delegate: PostControllerDelegate?, title: String?, subtitle: String?) {

        self.parentVC = parentVC
        self.postsList = IdentifiedArrayOf(uniqueElements: postsList)
        self.delegate = delegate
        titleView = GridPostTitleView(title: title ?? "", subtitle: subtitle ?? "")
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "SpotBlack")

        view.addSubview(collectionView)
        collectionView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addMapConfirmationView.isHidden = true
        view.addSubview(addMapConfirmationView)
        addMapConfirmationView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(34)
            $0.height.equalTo(57)
            $0.bottom.equalTo(-23)
        }

        if openComments {
            openComments(row: selectedPostIndex, animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setUpNavBar()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    func setPosts(posts: [MapPost]) {
        self.postsList = IdentifiedArrayOf(uniqueElements: posts)
        collectionView.reloadData()
    }

    private func setUpNavBar() {
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController?.navigationBar.shadowImage = UIImage()

        navigationItem.titleView = titleView

        if parentVC == .Map || parentVC == .Explore {
            if !(mapData?.likers.contains(where: { $0 == UserDataModel.shared.uid }) ?? true) {
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    image: UIImage(named: "AddPlusButton")?.withRenderingMode(.alwaysOriginal),
                    style: .plain,
                    target: self,
                    action: #selector(addMapTap))
            } else {
                navigationItem.rightBarButtonItem = UIBarButtonItem()
            }
        }
    }

    private func addNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(notifyImageChange(_:)), name: NSNotification.Name("PostImageChange"), object: nil)
    }

    @objc func notifyImageChange(_ notification: NSNotification) {
        if let index = notification.userInfo?.values.first as? Int {
            postsList[selectedPostIndex].selectedImageIndex = index
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout

extension GridPostViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return postsList.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        guard !postsList.isEmpty && postsList.count > indexPath.row else {
            return UICollectionViewCell()
        }
        
        let post = postsList[indexPath.row]
        if let videoURLString = post.videoURL,
           let videoURL = URL(string: videoURLString),
           let videoCell = collectionView.dequeueReusableCell(withReuseIdentifier: MapPostVideoCell.reuseID, for: indexPath) as? MapPostVideoCell {
            videoCell.configure(post: post, url: videoURL)
            videoCell.delegate = self
            return videoCell
            
        } else if let imageCell = collectionView.dequeueReusableCell(withReuseIdentifier: MapPostImageCell.reuseID, for: indexPath) as? MapPostImageCell {
            imageCell.configure(post: post, row: indexPath.row)
            imageCell.delegate = self
            return imageCell
            
        } else {
            return UICollectionViewCell()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.frame.size
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? MapPostImageCell {
            cell.animateLocation()
        } else if let cell = cell as? MapPostVideoCell {
            cell.playerView.player?.play()
            cell.animateLocation()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let videoCell = cell as? MapPostVideoCell else {
            return
        }
        
        videoCell.playerView.player?.pause()
        videoCell.playerView.player = nil
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0.0
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollView.contentInset.top = max((scrollView.frame.height - scrollView.contentSize.height) / 2, 0)
    }
}

extension GridPostViewController: ContentViewerDelegate {
    func tapToNextPost() {
        if selectedPostIndex < postsList.count - 1 {
            tapToSelectedRow(increment: 1)
        }
    }

    func tapToPreviousPost() {
        if selectedPostIndex > 0 {
            tapToSelectedRow(increment: -1)
        }
    }

    func tapToSelectedRow(increment: Int = 0) {
        self.collectionView.scrollToItem(at: IndexPath(item: selectedPostIndex + increment, section: 0), at: .top, animated: true)
    }

    func likePost(postID: String) {
        HapticGenerator.shared.play(.light)

        if postsList[selectedPostIndex].likers.firstIndex(where: { $0 == UserDataModel.shared.uid }) != nil {
            Mixpanel.mainInstance().track(event: "PostPageUnlikePost")
            unlikePost(id: postID)
        } else {
            Mixpanel.mainInstance().track(event: "PostPageLikePost")
            likePost(postID: postID)
        }
    }

    func openPostComments() {
        openComments(row: selectedPostIndex, animated: true)
    }

    func openPostActionSheet() {
        Mixpanel.mainInstance().track(event: "PostPageElipsesTap")
     //   addActionSheet()
    }

    func getSelectedPostIndex() -> Int {
        return selectedPostIndex
    }

    func openProfile(user: UserProfile) {
        let profileVC = ProfileViewController(userProfile: user)
        DispatchQueue.main.async { self.navigationController?.pushViewController(profileVC, animated: true) }
    }

    func openMap(mapID: String, mapName: String) {
        var map = CustomMap(
            founderID: "",
            imageURL: "",
            likers: [],
            mapName: mapName,
            memberIDs: [],
            posterIDs: [],
            posterUsernames: [],
            postIDs: [],
            postImageURLs: [],
            secret: false,
            spotIDs: []
        )

        map.id = mapID
        let customMapVC = CustomMapController(userProfile: nil, mapData: map, postsList: [])
        navigationController?.pushViewController(customMapVC, animated: true)
    }

    func openSpot(post: MapPost) {
        let spotVC = SpotPageController(mapPost: post)
        navigationController?.pushViewController(spotVC, animated: true)
    }

    func openComments(row: Int, animated: Bool) {
        if presentedViewController != nil { return }
        Mixpanel.mainInstance().track(event: "PostOpenComments")
        let post = postsList[row]
        let commentsVC = CommentsController(commentsList: post.commentList, post: post)
        commentsVC.delegate = self
        present(commentsVC, animated: animated, completion: nil)
    }

    private func likePost(id: String) {
        // TODO: update parent
        
        guard !id.isEmpty, var post = self.postsList[id: id] else {
            return
        }
        post.likers.append(UserDataModel.shared.uid)
        self.postsList[id: id] = post
        collectionView.reloadData()
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.postService?.likePostDB(post: post)
        }
    }

    private func unlikePost(id: String) {
        // TODO: update parent
        
        guard !id.isEmpty, var post = self.postsList[id: id] else {
            return
        }
        
        post.likers.removeAll(where: { $0 == UserDataModel.shared.uid })
        self.postsList[id: id] = post
        collectionView.reloadData()
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.postService?.unlikePostDB(post: post)
        }
    }

    @objc func addMapTap() {
        Mixpanel.mainInstance().track(event: "MapHeaderJoinTap")
        guard let map = mapData else { return }

        mapData?.likers.append(UserDataModel.shared.uid)
        if mapData?.communityMap ?? false { mapData?.memberIDs.append(UserDataModel.shared.uid) }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.mapService?.followMap(customMap: map) { _ in }
        }

        toggleAddMapView()
        setUpNavBar()

        guard let mapData = mapData else { return }
        NotificationCenter.default.post(Notification(name: Notification.Name("EditMap"), object: nil, userInfo: ["map": mapData as Any]))
    }

    private func toggleAddMapView() {
        addMapConfirmationView.isHidden = false
        addMapConfirmationView.alpha = 1.0
        UIView.animate(withDuration: 0.3, delay: 2.0, animations: { [weak self] in
            self?.addMapConfirmationView.alpha = 0.0
        }, completion: { [weak self] _ in
            self?.addMapConfirmationView.isHidden = true
            self?.addMapConfirmationView.alpha = 1.0
        })
    }
}

extension GridPostViewController: CommentsDelegate {
    func openProfileFromComments(user: UserProfile) {
        openProfile(user: user)
    }
}
