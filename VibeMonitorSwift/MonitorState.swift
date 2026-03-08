import SwiftUI
import Combine

@MainActor
class MonitorState: ObservableObject {
    // MARK: - Published State

    @Published var isConnected = false
    @Published var turns: [TurnData] = []
    @Published var activeTurn: ActiveTurnInfo?
    @Published var availableDates: [ArchiveEntry] = []
    @Published var historyTurns: [TurnData] = []
    @Published var todayStr: String = ""
    @Published var isLoadingHistory = false

    // MARK: - Server Config

    var serverHost: String = "localhost"
    var serverPort: Int = 8000
    var baseURL: String { "http://\(serverHost):\(serverPort)" }
    var wsURL: String { "ws://\(serverHost):\(serverPort)/ws" }

    // MARK: - Status Bar Callback

    /// Called whenever the menu bar text should be updated.
    /// AppDelegate sets this to update NSStatusItem.
    var onStatusBarUpdate: (() -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectDelay: TimeInterval = 3.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var isIntentionalDisconnect = false

    // MARK: - Computed Properties

    var totalTime: Double { turns.reduce(0) { $0 + $1.totalTime } }

    var avgTps: Double {
        let valid = turns.filter { $0.thinkingTps > 0 }
        return valid.isEmpty ? 0 : valid.reduce(0) { $0 + $1.thinkingTps } / Double(valid.count)
    }

    var totalThinkingTime: Double { turns.reduce(0) { $0 + $1.thinkingTime } }
    var totalToolTime: Double { turns.reduce(0) { $0 + $1.toolTime } }
    var totalOutputTime: Double { turns.reduce(0) { $0 + $1.outputTime } }
    var totalNetworkTime: Double { turns.reduce(0) { $0 + $1.networkTime } }
    var totalOtherTime: Double { turns.reduce(0) { $0 + $1.unaccountedTime } }

    var projectAggregation: [(name: String, turnCount: Int, totalTime: Double)] {
        let grouped = Dictionary(grouping: turns, by: { $0.projectName })
        return grouped.map { (name: $0.key, turnCount: $0.value.count, totalTime: $0.value.reduce(0) { $0 + $1.totalTime }) }
            .sorted { $0.totalTime > $1.totalTime }
    }

    var toolAggregation: [(name: String, count: Int, duration: Double)] {
        var stats: [String: (count: Int, duration: Double)] = [:]
        for turn in turns {
            for (toolName, count) in turn.toolBreakdown {
                stats[toolName, default: (0, 0)].count += count
            }
            for tool in turn.tools {
                stats[tool.tool, default: (0, 0)].duration += tool.duration
            }
        }
        return stats.map { (name: $0.key, count: $0.value.count, duration: $0.value.duration) }
            .sorted { $0.duration > $1.duration }
    }

    /// Compute stats from an arbitrary turn array (for history view reuse)
    static func computeStats(from turns: [TurnData]) -> (totalTime: Double, avgTps: Double, thinkingTime: Double, toolTime: Double, outputTime: Double, networkTime: Double, otherTime: Double) {
        let totalTime = turns.reduce(0) { $0 + $1.totalTime }
        let valid = turns.filter { $0.thinkingTps > 0 }
        let avgTps = valid.isEmpty ? 0 : valid.reduce(0) { $0 + $1.thinkingTps } / Double(valid.count)
        let thinkingTime = turns.reduce(0) { $0 + $1.thinkingTime }
        let toolTime = turns.reduce(0) { $0 + $1.toolTime }
        let outputTime = turns.reduce(0) { $0 + $1.outputTime }
        let networkTime = turns.reduce(0) { $0 + $1.networkTime }
        let otherTime = turns.reduce(0) { $0 + $1.unaccountedTime }
        return (totalTime, avgTps, thinkingTime, toolTime, outputTime, networkTime, otherTime)
    }

    // MARK: - Menu Bar Status Text

    enum StatusBarState {
        case idle
        case activeThinking(turnNumber: Int, elapsed: Double)
        case activeTool(turnNumber: Int, elapsed: Double, tool: String)
        case disconnected
        case noData
    }

    var statusBarState: StatusBarState {
        if !isConnected { return .disconnected }
        if let active = activeTurn {
            let elapsed = Date().timeIntervalSince(active.startTime)
            if let tool = active.currentTool {
                return .activeTool(turnNumber: active.turnNumber, elapsed: elapsed, tool: shortToolName(tool))
            } else {
                return .activeThinking(turnNumber: active.turnNumber, elapsed: elapsed)
            }
        }
        if turns.isEmpty { return .noData }
        return .idle
    }

    // MARK: - WebSocket Connection

    func connect() {
        isIntentionalDisconnect = false
        guard let url = URL(string: wsURL) else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        // Don't set isConnected here — wait for successful message receipt
        scheduleReceive()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        onStatusBarUpdate?()
    }

    private func scheduleReceive() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    if !self.isConnected {
                        self.isConnected = true
                        self.reconnectDelay = 3.0
                        self.onStatusBarUpdate?()
                    }
                    if case .string(let text) = message {
                        self.handleJson(text)
                    }
                    self.scheduleReceive()

                case .failure(let error):
                    print("WS Error: \(error)")
                    self.isConnected = false
                    self.activeTurn = nil
                    self.onStatusBarUpdate?()
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 1.5, maxReconnectDelay)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !self.isIntentionalDisconnect else { return }
            self.connect()
        }
    }

    // MARK: - Message Handling

    private func handleJson(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        guard let msg = try? decoder.decode(WSMessage.self, from: data) else {
            print("Failed to decode WS message: \(text.prefix(200))")
            return
        }

        switch msg.type {
        case .`init`:
            self.turns = msg.turns ?? []
            self.todayStr = msg.date ?? ""
            if msg.active == true {
                pollActiveTurn()
            }
            fetchAvailableHistory()
            onStatusBarUpdate?()

        case .turnStart:
            self.activeTurn = ActiveTurnInfo(
                turnNumber: msg.turnNumber ?? (turns.count + 1),
                startTime: Date(),
                projectName: msg.projectName
            )
            onStatusBarUpdate?()

        case .toolStart:
            if var active = activeTurn {
                active.currentTool = msg.tool
                active.currentToolDetail = msg.detail
                self.activeTurn = active
            }
            onStatusBarUpdate?()

        case .toolEnd:
            if var active = activeTurn {
                active.currentTool = nil
                active.currentToolDetail = nil
                self.activeTurn = active
            }
            onStatusBarUpdate?()

        case .turnComplete:
            if let newData = msg.data {
                self.turns.append(newData)
            }
            self.activeTurn = nil
            onStatusBarUpdate?()

        case .reset:
            self.turns = []
            self.activeTurn = nil
            onStatusBarUpdate?()
        }
    }

    // MARK: - Active Turn Polling

    private func pollActiveTurn() {
        guard let url = URL(string: "\(baseURL)/api/current") else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let resp = try JSONDecoder().decode(CurrentTurnResponse.self, from: data)
                if resp.active, let turnNum = resp.turnNumber {
                    let elapsed = resp.elapsed ?? 0
                    let startTime = Date().addingTimeInterval(-elapsed)
                    var info = ActiveTurnInfo(turnNumber: turnNum, startTime: startTime)
                    if let tool = resp.currentTool {
                        info.currentTool = tool
                    }
                    self.activeTurn = info
                    self.onStatusBarUpdate?()
                }
            } catch {
                print("Failed to poll active turn: \(error)")
            }
        }
    }

    // MARK: - HTTP APIs

    func fetchAvailableHistory() {
        guard let url = URL(string: "\(baseURL)/api/history") else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let resp = try JSONDecoder().decode(HistoryListResponse.self, from: data)
                self.availableDates = resp.archives
                self.todayStr = resp.today
            } catch {
                print("Failed to fetch history: \(error)")
            }
        }
    }

    func fetchHistoryForDate(_ date: String) {
        guard let url = URL(string: "\(baseURL)/api/history/\(date)") else { return }
        isLoadingHistory = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let resp = try JSONDecoder().decode(HistoryDateResponse.self, from: data)
                self.historyTurns = resp.turns ?? []
            } catch {
                self.historyTurns = []
                print("Failed to fetch history for \(date): \(error)")
            }
            self.isLoadingHistory = false
        }
    }

    func resetToday() {
        guard let url = URL(string: "\(baseURL)/api/reset") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        Task {
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
