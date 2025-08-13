import SwiftUI
import UniformTypeIdentifiers
import Foundation

// MARK: - LogReaderView for MAC4MAC App

struct LogReaderView: View {
    @State private var logEntries: [LogReaderEntry] = []
    @State private var isMonitoring = false
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var filterLevel: LogReaderEntry.LogLevel? = nil
    @State private var showOnlyErrors = false
    @State private var showOnlySessionID = ""
    @State private var monitoringTask: Task<Void, Never>?
    @State private var lastFileSize: UInt64 = 0
    @State private var selectedLogFile: URL?
    
    var filteredEntries: [LogReaderEntry] {
        var filtered = logEntries
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { entry in
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.sessionID.localizedCaseInsensitiveContains(searchText) ||
                entry.phase.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by log level
        if let level = filterLevel {
            filtered = filtered.filter { $0.level == level }
        }
        
        // Filter by errors only
        if showOnlyErrors {
            filtered = filtered.filter { $0.isError || $0.isTimeout }
        }
        
        // Filter by session ID
        if !showOnlySessionID.isEmpty {
            filtered = filtered.filter { $0.sessionID.contains(showOnlySessionID) }
        }
        
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            headerView
            
            // Main content
            HSplitView {
                // Sidebar with statistics
                sidebarView
                    .frame(minWidth: 250, maxWidth: 300)
                
                // Main log view
                logView
            }
        }
        .onAppear {
            loadCurrentLogFile()
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundColor(.blue)
            
            Text("MAC4MAC Log Reader")
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
            
            if let url = selectedLogFile {
                Text("Monitoring: \(url.lastPathComponent)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Clear Logs") {
                    logEntries.removeAll()
                }
                .buttonStyle(.borderless)
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                
                Button(isMonitoring ? "⏸ Pause" : "▶️ Monitor") {
                    toggleMonitoring()
                }
                .foregroundColor(isMonitoring ? .orange : .green)
                .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Analysis")
                .font(.headline)
                .padding(.bottom)
            
            // Filters
            Group {
                Text("Filters")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                
                Picker("Log Level", selection: $filterLevel) {
                    Text("All Levels").tag(LogReaderEntry.LogLevel?.none)
                    ForEach(LogReaderEntry.LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(LogReaderEntry.LogLevel?.some(level))
                    }
                }
                .pickerStyle(.menu)
                
                Toggle("🚨 Errors & Issues Only", isOn: $showOnlyErrors)
                    .toggleStyle(.checkbox)
                    .foregroundColor(showOnlyErrors ? .red : .primary)
                
                HStack {
                    Text("Session ID:")
                        .font(.caption)
                    TextField("Session", text: $showOnlySessionID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            
            Divider()
            
            // Statistics
            Group {
                Text("Statistics")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                statisticsView
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total Entries:")
                Spacer()
                Text("\(logEntries.count)")
                    .fontWeight(.medium)
            }
            
            HStack {
                Text("Filtered:")
                Spacer()
                Text("\(filteredEntries.count)")
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            Divider()
            
            // Count by level
            ForEach(LogReaderEntry.LogLevel.allCases, id: \.self) { level in
                let count = logEntries.filter { $0.level == level }.count
                if count > 0 {
                    HStack {
                        Text(level.rawValue)
                            .foregroundColor(level.color)
                        Spacer()
                        Text("\(count)")
                            .fontWeight(.medium)
                    }
                }
            }
            
            Divider()
            
            // Error counts with improved color scheme
            let errorCount = logEntries.filter { $0.isError }.count
            let timeoutCount = logEntries.filter { $0.isTimeout }.count
            let successCount = logEntries.filter { $0.isSuccess }.count
            let trackChangeCount = logEntries.filter { $0.isTrackChange }.count
            let sampleRateChangeCount = logEntries.filter { $0.isSampleRateChange }.count
            
            if errorCount > 0 {
                HStack {
                    Text("🚨 Errors:")
                        .foregroundColor(.red)
                    Spacer()
                    Text("\(errorCount)")
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
            
            if timeoutCount > 0 {
                HStack {
                    Text("⏱️ Timeouts:")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(timeoutCount)")
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
            }
            
            if successCount > 0 {
                HStack {
                    Text("✅ Success:")
                        .foregroundColor(.green)
                    Spacer()
                    Text("\(successCount)")
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
            
            if trackChangeCount > 0 {
                HStack {
                    Text("🎵 Track Changes:")
                        .foregroundColor(.purple)
                    Spacer()
                    Text("\(trackChangeCount)")
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                }
            }
            
            if sampleRateChangeCount > 0 {
                HStack {
                    Text("🎚️ Sample Rate:")
                        .foregroundColor(.mint)
                    Spacer()
                    Text("\(sampleRateChangeCount)")
                        .fontWeight(.medium)
                        .foregroundColor(.mint)
                }
            }
            
            // Session count
            let uniqueSessions = Set(logEntries.compactMap { $0.sessionID.isEmpty ? nil : $0.sessionID }).count
            if uniqueSessions > 0 {
                Divider()
                HStack {
                    Text("🔗 Active Sessions:")
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(uniqueSessions)")
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .font(.caption)
    }
    
    private var logView: some View {
        ScrollViewReader { proxy in
            List(filteredEntries) { entry in
                LogReaderEntryRow(entry: entry)
                    .id(entry.id)
            }
            .listStyle(PlainListStyle())
            .onChange(of: filteredEntries.count) { _, _ in
                if autoScroll && !filteredEntries.isEmpty {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(filteredEntries.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private func loadCurrentLogFile() {
        // Use the same log file that LogWriter is currently writing to
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logDir = cacheDir.appendingPathComponent("MAC4MAC_Logs")
        
        // Get today's log file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())
        let todayLogFile = logDir.appendingPathComponent("MAC4MAC_\(todayString).log")
        
        if fileManager.fileExists(atPath: todayLogFile.path) {
            selectedLogFile = todayLogFile
            loadLogFile(todayLogFile)
        }
    }
    
    private func loadLogFile(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            logEntries = lines.compactMap { line in
                LogReaderParser.parse(line)
            }
            
            // Get file size for monitoring
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            lastFileSize = attributes[.size] as? UInt64 ?? 0
            
        } catch {
            print("Error loading log file: \(error)")
        }
    }
    
    private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    private func startMonitoring() {
        guard let url = selectedLogFile else { return }
        
        isMonitoring = true
        
        monitoringTask = Task {
            while !Task.isCancelled && isMonitoring {
                await checkForNewLogEntries(url: url)
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second for more responsive updates
            }
        }
    }
    
    private func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    @MainActor
    private func checkForNewLogEntries(url: URL) async {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let currentSize = attributes[.size] as? UInt64 ?? 0
            
            // If file has grown, read new content
            if currentSize > lastFileSize {
                let fileHandle = try FileHandle(forReadingFrom: url)
                fileHandle.seek(toFileOffset: lastFileSize)
                let newData = fileHandle.readDataToEndOfFile()
                fileHandle.closeFile()
                
                if let newContent = String(data: newData, encoding: .utf8) {
                    let newLines = newContent.components(separatedBy: .newlines)
                    let newEntries = newLines.compactMap { line in
                        LogReaderParser.parse(line)
                    }
                    
                    logEntries.append(contentsOf: newEntries)
                }
                
                lastFileSize = currentSize
            }
        } catch {
            print("Error monitoring log file: \(error)")
        }
    }
}

// MARK: - LogReaderEntry Model (separate from main LogEntry to avoid conflicts)

struct LogReaderEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: String
    let level: LogLevel
    let sessionID: String
    let phase: String
    let status: String
    let timing: String
    let message: String
    let rawLine: String
    let isSeparator: Bool
    
    enum LogLevel: String, CaseIterable {
        case essential = "🎵 ESS"
        case normal = "ℹ️ NOR" 
        case debug = "🔍 DBG"
        case unknown = "❓ UNK"
        
        var color: Color {
            switch self {
            case .essential: return .primary  // Adapts to light/dark mode
            case .normal: return .secondary
            case .debug: return Color(NSColor.tertiaryLabelColor)
            case .unknown: return Color(NSColor.quaternaryLabelColor)
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .essential: return Color.accentColor.opacity(0.08)
            case .normal: return Color.blue.opacity(0.06)
            case .debug: return Color.gray.opacity(0.04)
            case .unknown: return Color.clear
            }
        }
    }
    
    var isError: Bool {
        return message.contains("❌") || message.contains("FAILED") || status == "ERR"
    }
    
    var isTimeout: Bool {
        return message.contains("⏰") || message.contains("TIMEOUT") || status == "TMO"
    }
    
    var isSuccess: Bool {
        return message.contains("✅") || message.contains("SUCCESS") || status == "OK"
    }
    
    var isStart: Bool {
        return message.contains("🚀") || message.contains("START") || status == "INIT"
    }
    
    var isStateChange: Bool {
        return message.contains("🔄") || message.contains("STATE") || status == "STATE"
    }
    
    var isSampleRateChange: Bool {
        return message.contains("🎚️") && (message.contains("⬆️") || message.contains("⬇️") || message.contains("➡️"))
    }
    
    var isTrackChange: Bool {
        return message.contains("NEW TRACK") || message.contains("Track change detected")
    }
    
    var priorityColor: Color {
        // First priority: Actual errors and issues (red/orange)
        if isError { return .red }
        if isTimeout { return .orange }
        
        // Second priority: Success operations (green, but subtle)
        if isSuccess { return Color.green.opacity(0.8) }
        
        // Third priority: Function-based coloring (logical grouping)
        if isTrackChange { return Color.purple }  // 🎵 Music/Track operations
        if isSampleRateChange { return Color.mint }  // 🎚️ Audio technical operations  
        if isStart { return Color.blue }  // 🚀 Initialization/startup operations
        if isStateChange { return Color.cyan }  // 🔄 State transitions
        
        // Default: Use log level coloring
        return level.color
    }
}

// MARK: - LogReaderParser

struct LogReaderParser {
    static func parse(_ line: String) -> LogReaderEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty lines
        if trimmed.isEmpty { return nil }
        
        // Handle separator lines
        if trimmed.hasPrefix("═══") {
            return LogReaderEntry(
                timestamp: "",
                level: .unknown,
                sessionID: "",
                phase: "",
                status: "",
                timing: "",
                message: trimmed,
                rawLine: line,
                isSeparator: true
            )
        }
        
        // Handle track info lines (🎵 NEW TRACK | ...)
        if trimmed.hasPrefix("🎵 NEW TRACK") {
            return LogReaderEntry(
                timestamp: "",
                level: .essential,
                sessionID: "",
                phase: "",
                status: "TRACK",
                timing: "",
                message: trimmed,
                rawLine: line,
                isSeparator: true
            )
        }
        
        // Parse standard log format: timestamp | level | [session][phase][status][timing] message
        let components = trimmed.components(separatedBy: " | ")
        guard components.count >= 3 else { return nil }
        
        let timestamp = components[0]
        let levelStr = components[1]
        let messageWithTags = components[2]
        
        // Parse log level
        let level = LogReaderEntry.LogLevel.allCases.first { levelStr.contains($0.rawValue) } ?? .unknown
        
        // Parse session, phase, status, timing from message
        var sessionID = ""
        var phase = ""
        var status = ""
        var timing = ""
        var message = messageWithTags
        
        // Extract tags using regex-like parsing
        if let sessionMatch = extractTag(from: messageWithTags, pattern: #"\[([A-F0-9]{8})\]"#) {
            sessionID = sessionMatch
        }
        
        if let phaseMatch = extractTag(from: messageWithTags, pattern: #"\[P([123])\]"#) {
            phase = "P\(phaseMatch)"
        }
        
        if let statusMatch = extractTag(from: messageWithTags, pattern: #"\[(INIT|OK|ERR|TMO|CACHE|STATE|SKIP)\]"#) {
            status = statusMatch
        }
        
        if let timingMatch = extractTag(from: messageWithTags, pattern: #"\[(\d+)ms\]"#) {
            timing = "\(timingMatch)ms"
        }
        
        // Clean message by removing tags
        message = messageWithTags
            .replacingOccurrences(of: #"\[[A-F0-9]{8}\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[P[123]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[(INIT|OK|ERR|TMO|CACHE|STATE|SKIP)\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\d+ms\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        return LogReaderEntry(
            timestamp: timestamp,
            level: level,
            sessionID: sessionID,
            phase: phase,
            status: status,
            timing: timing,
            message: message,
            rawLine: line,
            isSeparator: false
        )
    }
    
    private static func extractTag(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        if match.numberOfRanges > 1 {
            let captureRange = match.range(at: 1)
            if let range = Range(captureRange, in: text) {
                return String(text[range])
            }
        }
        return nil
    }
}

// MARK: - LogReaderEntryRow View

struct LogReaderEntryRow: View {
    let entry: LogReaderEntry
    
    var body: some View {
        if entry.isSeparator {
            separatorView
        } else {
            logEntryView
        }
    }
    
    private var separatorView: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.vertical, 4)
            Divider()
        }
        .background(Color.accentColor.opacity(0.05))
    }
    
    private var logEntryView: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.timestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Level badge
            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.level.backgroundColor)
                .foregroundColor(entry.level.color)
                .cornerRadius(4)
            
            // Session and Phase info
            HStack(spacing: 4) {
                if !entry.sessionID.isEmpty {
                    Text(entry.sessionID)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(3)
                }
                
                if !entry.phase.isEmpty {
                    Text(entry.phase)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(3)
                }
                
                if !entry.status.isEmpty {
                    Text(entry.status)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(statusBackgroundColor(entry.status))
                        .foregroundColor(statusForegroundColor(entry.status))
                        .cornerRadius(3)
                }
                
                if !entry.timing.isEmpty {
                    Text(entry.timing)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(3)
                }
            }
            
            // Message
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(entry.priorityColor)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 2)
        .background(
            // Only highlight actual problems with colored backgrounds
            entry.isError ? Color.red.opacity(0.15) :
            entry.isTimeout ? Color.orange.opacity(0.1) :
            Color.clear
        )
        .cornerRadius(4)
    }
    
    private func statusBackgroundColor(_ status: String) -> Color {
        switch status {
        case "OK": return Color.green.opacity(0.2)
        case "ERR": return Color.red.opacity(0.2)
        case "TMO": return Color.orange.opacity(0.2)
        case "INIT": return Color.blue.opacity(0.2)
        default: return Color.gray.opacity(0.2)
        }
    }
    
    private func statusForegroundColor(_ status: String) -> Color {
        switch status {
        case "OK": return Color.green
        case "ERR": return Color.red
        case "TMO": return Color.orange
        case "INIT": return Color.blue
        default: return Color.gray
        }
    }
}
