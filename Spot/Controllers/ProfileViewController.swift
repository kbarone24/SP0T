//
//  ProfileViewController.swift
//  Spot
//
//  Created by Kenny Barone on 6/6/22.
//  Copyright © 2022 sp0t, LLC. All rights reserved.
//

import UIKit

class ProfileViewController: UIViewController {
        
    // function for adding profileViewController
    @objc func addView(_ sender: UIButton){
        let newVC = ProfileViewController()
        navigationController?.pushViewController(newVC, animated: true)
    }
    
    var userProfile : UserProfile?
    
    init(userProfile: UserProfile? = nil) {
            self.userProfile = userProfile == nil ? UserDataModel.shared.userInfo : userProfile
            
            /*rest of init*/
            
            super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1), alpha: 1.0)
        modalPresentationStyle = .custom
        let myButton = UIButton(type: .system)///dummy button for adding profile view
        myButton.frame = CGRect(x: 20, y: 130, width: 100, height: 50)
        myButton.setTitle("AddView", for: .normal)
        myButton.addTarget(self, action: #selector(addView(_:)), for: .touchUpInside)
        view.addSubview(myButton)
    }
}
