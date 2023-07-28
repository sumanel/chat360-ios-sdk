//
//  ViewController.swift
//  CHAT360IOS_SDK
//
//  Created by prateekgupta360 on 07/28/2023.
//  Copyright (c) 2023 prateekgupta360. All rights reserved.
//

import UIKit
import CHAT360IOS_SDK

class ViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let config = ChatConfigs(botId: "f0efe1c0-cbe9-4320-859b-e594cd7fc46f", appId: "com.chat360.chat360demoapp")
        ChatLauncher.showChat(with: config, parentController: self)
    }
    
    // ...
}

