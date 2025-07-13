//
//  FeatureToggle.swift
//  MAC4MAC
//
//  Created by Akshat Singhal on 5/7/2025.
//


import Foundation

enum FeatureToggle: String, CaseIterable {
    case logging
    case playlistManagement
    case httpServer
    case futureDSPEnhancement
    case aiAnalysis

    var displayName: String {
        switch self {
        case .logging: return "Verbose Logging"
        case .playlistManagement: return "Playlist Creation"
        case .httpServer: return "HTTP Server"
        case .futureDSPEnhancement: return "Real-Time DSP"
        case .aiAnalysis: return "AI Analysis"
        }
    }
}
