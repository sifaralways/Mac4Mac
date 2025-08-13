//
//  ContentView.swift
//  MAC4MAC
//
//  Created by Akshat Singhal on 22/6/2025.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MainAppView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "music.note")
                    Text("Music Control")
                }
                .tag(0)
            
            LogReaderView()
                .tabItem {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Log Reader")
                }
                .tag(1)
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
}

struct MainAppView: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("MAC4MAC")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Audio Control with iOS Remote")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicators
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Audio System Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("Network Server Active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Track Monitoring")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Main content area
            HStack(spacing: 20) {
                // Left panel - Current track info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Track")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Track Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Unknown Track")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Artist")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Unknown Artist")
                            .font(.headline)
                        
                        Text("Album")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Unknown Album")
                            .font(.subheadline)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                
                // Right panel - Audio settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio Settings")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Sample Rate:")
                                .frame(width: 100, alignment: .leading)
                            Text("44.1 kHz")
                                .fontWeight(.medium)
                            Spacer()
                            Text("🎚️")
                        }
                        
                        HStack {
                            Text("Bit Depth:")
                                .frame(width: 100, alignment: .leading)
                            Text("16-bit")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        HStack {
                            Text("Network:")
                                .frame(width: 100, alignment: .leading)
                            Text("Connected")
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            Spacer()
                            Text("📱")
                        }
                        
                        Divider()
                        
                        Text("Quick Actions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 12) {
                            Button("View Logs") {
                                selectedTab = 1
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Clear Cache") {
                                // Action for clearing cache
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
