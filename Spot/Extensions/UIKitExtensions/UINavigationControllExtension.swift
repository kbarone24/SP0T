//
//  UINavigationControllExtension.swift
//  Spot
//
//  Created by Kenny Barone on 2/17/23.
//  Copyright © 2023 sp0t, LLC. All rights reserved.
//

import Foundation
import UIKit

extension UINavigationController {
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        navigationBar.topItem?.backButtonDisplayMode = .minimal
    }

    func setUpDarkNav(translucent: Bool) {
        setNavigationBarHidden(false, animated: true)

        navigationBar.isTranslucent = translucent
        navigationBar.barStyle = .black
        navigationBar.tintColor = UIColor.white
        navigationBar.shadowImage = UIImage()
        navigationBar.setBackgroundImage(UIImage(color: UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1.00)), for: .default)
        // navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        //  navigationBar.backgroundColor = UIColor(named: "SpotBlack")

        navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont(name: "SFCompactText-Heavy", size: 19) as Any
        ]
    }
}
