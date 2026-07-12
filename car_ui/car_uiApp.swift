//
//  car_uiApp.swift
//  car_ui
//
//  Created by Sena Takasawa on 2026/2/20.
//

import GoogleMobileAds
import SwiftUI

@main
struct car_uiApp: App {
    init() {
        MobileAds.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
