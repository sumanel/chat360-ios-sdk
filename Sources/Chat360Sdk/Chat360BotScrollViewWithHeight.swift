//
//  SwiftUIView.swift
//  
//
//  Created by Harshit Sharma on 19/11/24.
//

import SwiftUI

@available(iOS 13.0, *)
public struct Chat360BotScrollViewWithHeight: View {
    let botConfig: Chat360Config
    let height: CGFloat

    public init(botConfig: Chat360Config, height: CGFloat) {
        self.botConfig = botConfig
        self.height = height
    }
    
    public var body: some View {
        ScrollView {
            Chat360BotView(botConfig: botConfig)
                .frame(height: height)
        }
    }
}

