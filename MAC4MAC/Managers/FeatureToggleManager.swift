// FeatureToggleManager.swift
// MAC4MAC

import Foundation

class FeatureToggleManager {
    private static let prefix = "MAC4MAC.FeatureToggle."

    static func isEnabled(_ feature: FeatureToggle) -> Bool {
        UserDefaults.standard.object(forKey: key(for: feature)) == nil
            ? defaultValue(for: feature)
            : UserDefaults.standard.bool(forKey: key(for: feature))
    }

    static func set(_ feature: FeatureToggle, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key(for: feature))
    }

    static func toggle(_ feature: FeatureToggle) {
        let current = isEnabled(feature)
        set(feature, enabled: !current)
    }

    static func key(for feature: FeatureToggle) -> String {
        return prefix + feature.rawValue
    }

    static func defaultValue(for feature: FeatureToggle) -> Bool {
        switch feature {
        case .logging:
            return true
        case .playlistManagement:
            return true
        case .httpServer:
            return true
        case .futureDSPEnhancement:
            return false
        case .aiAnalysis:
            return false
        }
    }
}
