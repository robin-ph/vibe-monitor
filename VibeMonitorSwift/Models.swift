import Foundation

// MARK: - Turn Data (from server JSON)

struct TurnData: Codable, Identifiable {
    let id: String
    let turnNumber: Int
    let startTime: Double
    let totalTime: Double
    let thinkingTime: Double
    let thinkingTokens: Int
    let thinkingTps: Double
    let toolTime: Double
    let toolTimeHook: Double?
    let toolTimeRecovered: Double?
    let toolCount: Int
    let toolBreakdown: [String: Int]
    let tools: [ToolEntry]
    let outputTime: Double
    let outputChars: Int?
    let networkTime: Double
    let unaccountedTime: Double
    let apiCalls: Int?
    let projectId: String?
    let projectName: String

    enum CodingKeys: String, CodingKey {
        case id
        case turnNumber = "turn_number"
        case startTime = "start_time"
        case totalTime = "total_time"
        case thinkingTime = "thinking_time"
        case thinkingTokens = "thinking_tokens"
        case thinkingTps = "thinking_tps"
        case toolTime = "tool_time"
        case toolTimeHook = "tool_time_hook"
        case toolTimeRecovered = "tool_time_recovered"
        case toolCount = "tool_count"
        case toolBreakdown = "tool_breakdown"
        case tools
        case outputTime = "output_time"
        case outputChars = "output_chars"
        case networkTime = "network_time"
        case unaccountedTime = "unaccounted_time"
        case apiCalls = "api_calls"
        case projectId = "project_id"
        case projectName = "project_name"
    }
}

struct ToolEntry: Codable, Identifiable {
    let id: String
    let tool: String
    let duration: Double
    let detail: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tool = try container.decode(String.self, forKey: .tool)
        self.duration = try container.decode(Double.self, forKey: .duration)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.id = UUID().uuidString
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tool, forKey: .tool)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(detail, forKey: .detail)
    }

    enum CodingKeys: String, CodingKey {
        case tool, duration, detail
    }
}

// MARK: - Active Turn (local tracking)

struct ActiveTurnInfo {
    let turnNumber: Int
    let startTime: Date
    var currentTool: String?
    var currentToolDetail: String?
    var projectName: String?
}

// MARK: - API Responses

struct TurnsResponse: Codable {
    let turns: [TurnData]
    let date: String
}

struct CurrentTurnResponse: Codable {
    let active: Bool
    let turnNumber: Int?
    let elapsed: Double?
    let toolTime: Double?
    let toolCount: Int?
    let currentTool: String?

    enum CodingKeys: String, CodingKey {
        case active
        case turnNumber = "turn_number"
        case elapsed
        case toolTime = "tool_time"
        case toolCount = "tool_count"
        case currentTool = "current_tool"
    }
}

struct HistoryListResponse: Codable {
    let today: String
    let archives: [ArchiveEntry]
}

struct ArchiveEntry: Codable, Identifiable {
    var id: String { date }
    let date: String
    let turns: Int
    let totalTime: Double

    enum CodingKeys: String, CodingKey {
        case date, turns
        case totalTime = "total_time"
    }
}

struct HistoryDateResponse: Codable {
    let date: String?
    let turns: [TurnData]?
    let error: String?
}

// MARK: - WebSocket Messages

struct WSMessage: Codable {
    enum MessageType: String, Codable {
        case `init`
        case turnStart = "turn_start"
        case toolStart = "tool_start"
        case toolEnd = "tool_end"
        case turnComplete = "turn_complete"
        case reset
    }

    let type: MessageType
    let turns: [TurnData]?
    let active: Bool?
    let date: String?
    let turnNumber: Int?
    let projectName: String?
    let ts: Double?
    let tool: String?
    let detail: String?
    let data: TurnData?

    enum CodingKeys: String, CodingKey {
        case type, turns, active, date, ts, tool, detail, data
        case turnNumber = "turn_number"
        case projectName = "project_name"
    }
}
