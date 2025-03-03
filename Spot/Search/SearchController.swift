//
//  SearchController.swift
//  Spot
//
//  Created by Kenny Barone on 6/15/23.
//  Copyright © 2023 sp0t, LLC. All rights reserved.
//

import Combine
import Foundation
import UIKit
import Mixpanel

class SearchController: UIViewController {
    typealias Input = SearchViewModel.Input
    typealias DataSource = UITableViewDiffableDataSource<Section, Item>
    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>

    private let viewModel: SearchViewModel
    private let searchText = PassthroughSubject<String, Never>()
    private var subscriptions = Set<AnyCancellable>()

    private lazy var dataSource: DataSource = {
        let dataSource = DataSource(tableView: tableView) { tableView, indexPath, item in
            switch item {
            case .item(let searchResult):
                let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseID, for: indexPath) as? SearchResultCell
                cell?.configure(searchResult: searchResult)
                return cell
            }
        }
        return dataSource
    }()

    enum Section: Hashable {
        case main
    }

    enum Item: Hashable {
        case item(searchResult: SearchResult)
    }

    private(set) lazy var searchBarContainer = UIView()
    private(set) lazy var searchBar: UISearchBar = {
        let searchBar = SpotSearchBar()
        searchBar.searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Search for friends and spots",
            attributes: [NSAttributedString.Key.foregroundColor: UIColor(red: 0.671, green: 0.671, blue: 0.671, alpha: 1)]
        )
        return searchBar
    }()

    lazy var tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = UIColor(named: "SpotBlack")
        table.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 300, right: 0)
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.reuseID)
        table.rowHeight = UITableView.automaticDimension
        return table
    }()

    private(set) lazy var activityIndicator = UIActivityIndicatorView()

    private var isWaitingForDatabaseFetch = false {
        didSet {
            DispatchQueue.main.async {
                if self.isWaitingForDatabaseFetch {
                    self.tableView.layoutIfNeeded()
                    let tableOffset = self.tableView.contentSize.height + 10
                    self.activityIndicator.snp.removeConstraints()
                    self.activityIndicator.snp.makeConstraints {
                        $0.centerX.equalToSuperview()
                        $0.width.height.equalTo(30)
                        $0.top.equalTo(tableOffset)
                    }
                    self.activityIndicator.startAnimating()
                } else {
                    self.activityIndicator.stopAnimating()
                }
            }
        }
    }

    
    init(viewModel: SearchViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setUpNavBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()

        Mixpanel.mainInstance().track(event: "SearchAppeared")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "SpotBlack")

        navigationItem.titleView = searchBar
        searchBar.delegate = self

        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints {
            $0.top.equalTo(0)
            $0.leading.trailing.bottom.equalToSuperview()
        }

        tableView.addSubview(activityIndicator)
        activityIndicator.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.top.equalTo(tableView).offset(100)
            $0.width.height.equalTo(30)
        }
        activityIndicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)


        let input = Input(searchText: searchText)
        let output = viewModel.bind(to: input)

        output.snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.dataSource.apply(snapshot, animatingDifferences: false)
                self?.isWaitingForDatabaseFetch = false
            }
            .store(in: &subscriptions)
    }

    private func setUpNavBar() {
        navigationController?.setUpOpaqueNav(backgroundColor: SpotColors.SpotBlack.color)
    }
}

extension SearchController: UISearchBarDelegate, UITextViewDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText.send(searchText)
        self.isWaitingForDatabaseFetch = true
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension SearchController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.snapshot().numberOfItems
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        var vc = UIViewController()
        switch item {
        case .item(let searchResult):
            switch searchResult.type {
            case .user:
                Mixpanel.mainInstance().track(event: "SearchUserTap")
                guard let user = searchResult.user else { return }
                let profileVC = ProfileViewController(viewModel: ProfileViewModel(serviceContainer: ServiceContainer.shared, profile: user))
                vc = profileVC

            case .spot:
                Mixpanel.mainInstance().track(event: "SearchSpotTap")
                guard let spot = searchResult.spot else { return }
                let spotVC = SpotController(viewModel: SpotViewModel(serviceContainer: ServiceContainer.shared, spot: spot, passedPostID: nil, passedCommentID: nil))
                vc = spotVC
                
            case .map:
                Mixpanel.mainInstance().track(event: "SearchMapTap")
                guard let map = searchResult.map else { return }
                let mapVC = CustomMapController(viewModel: CustomMapViewModel(serviceContainer: ServiceContainer.shared, map: map, passedPostID: "", passedCommentID: ""))
                vc = mapVC
            }
        }
        DispatchQueue.main.async {
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
}
