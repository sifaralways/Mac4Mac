//
//  FeatureToggleManager.swift
//  MAC4MAC
//
//  Created by Akshat Singhal on 5/7/2025.
//


import Foundation

class FeatureToggleManager {
    private static let prefix = "MAC4MAC.FeatureToggle."

    static func isEnabled(_ feature: FeatureToggle) -> Bool {
        UserDefaults.standard.bool(forKey: prefix + feature.rawValue)
    }

    static func set(_ feature: FeatureToggle, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: prefix + feature.rawValue)
    }

    static func toggle(_ feature: FeatureToggle) {
        let current = isEnabled(feature)
        set(feature, enabled: !current)
    }
}
