# Vibe Monitor - macOS Native Menu Bar App Design Spec

> 给 Flash 的实现规格书。基于现有 Python FastAPI server，用 Swift/SwiftUI 原生开发 macOS 菜单栏客户端。

---

## 1. 项目概述

### 1.1 目标
将现有网页端 Dashboard (index.html + script.js) 的全部功能迁移到 macOS 原生菜单栏应用，同时保留 FastAPI server 不变。

### 1.2 技术栈
- **语言**: Swift 5.9+
- **UI**: SwiftUI (macOS 13 Ventura+)
- **图表**: Swift Charts framework
- **网络**: URLSession (HTTP) + URLSessionWebSocketTask (WebSocket)
- **架构**: 混合 AppKit + SwiftUI (NSStatusItem + NSPopover + SwiftUI Views)
- **最低系统**: macOS 13.0

### 1.3 为什么用混合方案而非纯 MenuBarExtra
- 需要动态更新菜单栏文字（实时显示 Turn 编号、计时、工具名）
- MenuBarExtra 对动态文字更新支持有限
- 需要精细控制 NSStatusItem 按钮的样式（颜色、字体）

---

## 2. 信息架构：三层渐进展开

```
第一层: 菜单栏图标 (始终可见, 22pt高, 0交互成本)
  └─ 最关键的 1-2 个指标

第二层: Popover 弹窗 (点击图标, 360x520pt)
  └─ 3个Tab: Live / Today / History
  └─ 承载网页端 90% 的信息

第三层: 独立窗口 (可选, 点按钮打开)
  └─ 完整图表 + Turn 详情展开
```

---

## 3. 第一层：菜单栏图标

### 3.1 布局

```
[icon] [状态文字]
```

- 图标: SF Symbol `bolt.fill`，固定
- 文字: 动态切换，根据状态不同展示不同内容
- 使用 `NSStatusItem.variableLength` 自适应宽度

### 3.2 状态切换逻辑

| 状态 | 条件 | 显示文字 | 图标颜色 |
|------|------|---------|---------|
| 空闲 (Idle) | 已连接，无活跃Turn | `12 turns · 45m` | 默认(template) |
| 活跃-思考中 | Turn活跃，无工具在执行 | `T5 ⏱32s` | 紫色 #a78bfa |
| 活跃-工具执行 | Turn活跃，有工具正在执行 | `T5 ⏱32s Edit` | 黄色 #fbbf24 |
| 断开连接 | WebSocket断开 | `offline` | 红色 #fb7185 |
| 无数据 | 已连接，今日0个Turn | `ready` | 灰色 |

### 3.3 更新频率
- 空闲状态: 每次收到 turn_complete 消息时更新
- 活跃状态: 每 0.5 秒刷新计时器
- 用 `NSAttributedString` 给图标文字上色

### 3.4 实现要点
```swift
// 用 NSAttributedString 实现彩色文字
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor(hex: "#a78bfa") // 紫色=思考中
]
statusItem.button?.attributedTitle = NSAttributedString(string: "T5 ⏱32s", attributes: attrs)
```

---

## 4. 第二层：Popover 弹窗

### 4.1 整体结构

```
┌─────────────────────────── 360pt ──────────────────────────┐
│  Header: 标题 + 连接状态                          48pt    │
│  Tab Bar: [Live] [Today] [History]                32pt    │
│  ────────────────────────────────────────────              │
│  Tab Content (可滚动)                          ~400pt     │
│  ────────────────────────────────────────────              │
│  Footer: 操作按钮                                 40pt    │
└───────────────────────────────────────── total ~520pt ────┘
```

### 4.2 Header 区

```
⚡ Vibe Monitor                    🟢 Connected
```

- 左侧: SF Symbol `bolt.fill` + "Vibe Monitor" (font: .headline)
- 右侧: 连接状态圆点 + 文字
  - 🟢 Connected (绿色 #34d399)
  - 🔴 Disconnected (红色 #fb7185)，断开时带重连计时

### 4.3 Tab Bar

使用 SwiftUI `Picker` with `.segmented` style:

```swift
Picker("View", selection: $selectedTab) {
    Text("Live").tag(Tab.live)
    Text("Today").tag(Tab.today)
    Text("History").tag(Tab.history)
}
.pickerStyle(.segmented)
```

---

## 5. Tab 1: Live (实时视图)

这是最常看的页面，**对应网页端的「Active Turn 指示器」+「Turn 列表」**。

### 5.1 布局

```
┌───────────────────────────────────────────┐
│ ┌─ Active Turn ─────────────────────────┐ │
│ │ 🔴 Turn #5            elapsed 32.1s  │ │
│ │ ████████████░░░░░░░░░  thinking      │ │
│ │ 🔧 Edit → server.py                  │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ Recent Turns                              │
│ ┌───────────────────────────────────────┐ │
│ │ T4  89 t/s                     12.3s │ │
│ │ ██████████░░░░  think 8.1 tool 3.2   │ │
│ │ Edit ×2  Bash ×1                     │ │
│ ├───────────────────────────────────────┤ │
│ │ T3  92 t/s                      8.7s │ │
│ │ ████████░░░░░░  think 5.2 tool 2.8   │ │
│ │ Grep ×1  Read ×3                     │ │
│ ├───────────────────────────────────────┤ │
│ │ T2  67 t/s                     24.5s │ │
│ │ ████░░░░░░░░░░  think 9.8 tool 13.2  │ │
│ │ Bash ×5                              │ │
│ ├───────────────────────────────────────┤ │
│ │ ... (ScrollView, 最多显示最近 10 条)   │ │
│ └───────────────────────────────────────┘ │
└───────────────────────────────────────────┘
```

### 5.2 Active Turn 卡片

仅当 `current_turn != nil` 时显示，卡片背景用微弱的紫色渐变暗示"进行中"。

| 元素 | 说明 |
|------|------|
| 脉冲圆点 | SwiftUI 动画 `.opacity` 循环 0.3↔1.0，红色 |
| Turn 编号 | "Turn #5"，font: .subheadline.bold() |
| 计时器 | 每 0.5s 更新，font: .monospacedDigit，右对齐 |
| 进度条 | 不确定进度条(indeterminate)或静态条 |
| 当前阶段 | "thinking" / "tool: Edit" 等 |
| 工具详情 | 工具名 + detail（如 "Edit → server.py"），灰色小字 |

**数据来源**: WebSocket `turn_start` / `tool_start` / `tool_end` 消息 + 本地计时器

### 5.3 Recent Turns 列表

每个 Turn 一行精简卡片，**对应网页端 Turn 详情卡片的压缩版**。

每个卡片包含：

```
行1: [T编号] [TPS badge]                    [总时间]
行2: [迷你堆叠条形图 ████████░░░░]  think Xs  tool Ys
行3: [工具标签] Edit ×2  Bash ×1
```

| 元素 | 对应网页端 | 实现 |
|------|-----------|------|
| Turn 编号 | `turn_number` | "T4" |
| TPS badge | `thinking_tps` | "89 t/s"，紫色小标签 |
| 总时间 | `total_time` | "12.3s"，右对齐，monospaced |
| 迷你条形图 | Turn 详情中的彩色条 | SwiftUI `GeometryReader` 画比例条 |
| 时间摘要 | thinking_time + tool_time | "think 8.1 tool 3.2" |
| 工具标签 | `tool_breakdown` | 每个工具名+次数，用小圆角标签 |

### 5.4 迷你堆叠条形图

这是将网页端那个大的 Stacked Bar Chart **内联到每个 Turn 行**的关键设计。

```swift
// 每个Turn行内的迷你条形图 (高度 6pt, 圆角)
HStack(spacing: 0) {
    Rectangle().fill(Color.purple.opacity(0.8))  // thinking
        .frame(width: totalWidth * thinkingPct)
    Rectangle().fill(Color.yellow.opacity(0.8))  // tool
        .frame(width: totalWidth * toolPct)
    Rectangle().fill(Color.blue.opacity(0.8))    // output
        .frame(width: totalWidth * outputPct)
    Rectangle().fill(Color.pink.opacity(0.8))    // network+other
        .frame(width: totalWidth * otherPct)
}
.frame(height: 6)
.clipShape(RoundedRectangle(cornerRadius: 3))
```

### 5.5 没有活跃 Turn 时

Active Turn 卡片隐藏，显示一个安静的状态行：
```
💤 Idle — waiting for next turn
```

---

## 6. Tab 2: Today (今日统计)

**对应网页端的「统计卡片」+「饼图」+「项目筛选」**。

### 6.1 布局

```
┌───────────────────────────────────────────┐
│ ┌────────┐ ┌────────┐ ┌────────┐         │
│ │   12   │ │ 45m32s │ │   89   │         │
│ │ Turns  │ │  Time  │ │ tok/s  │         │
│ └────────┘ └────────┘ └────────┘         │
│                                           │
│ Time Breakdown                            │
│ ┌───────────────────────────────────────┐ │
│ │ Thinking ████████████████░░░░  62%    │ │
│ │ Tool     █████████░░░░░░░░░░░  21%    │ │
│ │ Output   ████░░░░░░░░░░░░░░░░  11%    │ │
│ │ Other    ██░░░░░░░░░░░░░░░░░░   6%    │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ Projects                                  │
│ ┌───────────────────────────────────────┐ │
│ │ 🟣 coding-moniter    4 turns   32m   │ │
│ │ 🔵 hyperrouter       2 turns   13m   │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ Top Tools                                 │
│ ┌───────────────────────────────────────┐ │
│ │ Read     7×    ██████████  320.0s     │ │
│ │ Bash    11×    ████████     18.3s     │ │
│ │ Task     2×    ██████████  524.0s     │ │
│ │ WebSearch 16×  ████████    234.0s     │ │
│ │ WebFetch  19×  █████████   265.2s     │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ [Reset Today]                             │
└───────────────────────────────────────────┘
```

### 6.2 统计卡片

3 个并排小卡片：

| 卡片 | 数值 | 计算方式 |
|------|------|---------|
| Turns | 12 | `turns.count` |
| Time | 45m 32s | `turns.reduce(0) { $0 + $1.totalTime }` → 格式化 |
| tok/s | 89 | 有 thinking_tps > 0 的 turn 取平均 |

样式: 数值用 `.title.bold()`, 标签用 `.caption`, 卡片背景 `.quaternarySystemFill`

### 6.3 Time Breakdown (替代网页端饼图)

用**水平条形图**替代饼图，更省空间、更易读。

每行：标签 + 比例条 + 百分比

```swift
struct BreakdownRow: View {
    let label: String
    let value: Double    // 秒数
    let total: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 60, alignment: .leading)
                .font(.caption)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.7))
                    .frame(width: geo.size.width * (value / max(total, 1)))
            }
            .frame(height: 8)
            Text("\(Int(value / max(total, 1) * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 35, alignment: .trailing)
        }
    }
}
```

4 个分类及颜色（与网页端一致）：
| 分类 | 颜色 | 计算 |
|------|------|------|
| Thinking | #a78bfa (紫) | `sum(thinking_time)` |
| Tool | #fbbf24 (黄) | `sum(tool_time)` |
| Output | #38bdf8 (蓝) | `sum(output_time)` |
| Other | #94a3b8 (灰) | `sum(network_time + unaccounted_time)` |

### 6.4 Projects 区

**对应网页端的项目筛选器(chips)**，改为列表行。

每行: 颜色圆点 + 项目名 + turns数 + 总时间

```swift
ForEach(projects) { project in
    HStack {
        Circle().fill(project.color).frame(width: 8, height: 8)
        Text(project.name).font(.caption)
        Spacer()
        Text("\(project.turnCount) turns").font(.caption2).foregroundStyle(.secondary)
        Text(formatTime(project.totalTime)).font(.caption.monospacedDigit())
    }
}
```

数据聚合逻辑：按 `project_name` 分组，统计 turn 数和总时间。

### 6.5 Top Tools 区

**网页端没有这个视图，从 Turn 详情中聚合而来**，在菜单栏很有价值。

按工具名聚合所有 Turn 的 tools 数组：
```swift
// 聚合逻辑
var toolStats: [String: (count: Int, duration: Double)] = [:]
for turn in turns {
    for (toolName, count) in turn.toolBreakdown {
        toolStats[toolName, default: (0, 0)].count += count
    }
    for tool in turn.tools {
        toolStats[tool.tool, default: (0, 0)].duration += tool.duration
    }
}
// 按总耗时排序
let sorted = toolStats.sorted { $0.value.duration > $1.value.duration }
```

每行: 工具名 + 调用次数 + 小条 + 耗时

### 6.6 Reset 按钮

底部放一个 "Reset Today" 按钮，调用 `POST /api/reset`。需要确认弹窗。

---

## 7. Tab 3: History (历史视图)

**对应网页端的「日期导航」+ 历史数据查看**。

### 7.1 布局

```
┌───────────────────────────────────────────┐
│  ◀  Thu, Mar 7, 2026  ▶     [Today]      │
│                                           │
│ ┌────────┐ ┌────────┐ ┌────────┐         │
│ │    8   │ │ 1h 12m │ │   76   │         │
│ │ Turns  │ │  Time  │ │ tok/s  │         │
│ └────────┘ └────────┘ └────────┘         │
│                                           │
│ Time Breakdown                            │
│ ┌───────────────────────────────────────┐ │
│ │ Thinking ████████████░░░░░░░░  58%    │ │
│ │ Tool     ██████████░░░░░░░░░░  32%    │ │
│ │ Output   ███░░░░░░░░░░░░░░░░░   7%    │ │
│ │ Other    █░░░░░░░░░░░░░░░░░░░   3%    │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ Turns                                     │
│ ┌───────────────────────────────────────┐ │
│ │ T1  82 t/s  Edit ×3 Bash ×1   18.2s │ │
│ │ T2  91 t/s  Read Grep           6.4s │ │
│ │ T3  68 t/s  Bash ×5           45.1s  │ │
│ │ ...                                   │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ Available Dates                           │
│ ┌───────────────────────────────────────┐ │
│ │ Mar 7   8 turns   1h 12m             │ │
│ │ Mar 6  15 turns   2h 45m             │ │
│ │ Mar 5   6 turns     38m              │ │
│ └───────────────────────────────────────┘ │
└───────────────────────────────────────────┘
```

### 7.2 日期导航

```swift
HStack {
    Button(action: goToPreviousDate) {
        Image(systemName: "chevron.left")
    }
    .disabled(!hasPreviousDate)

    Text(formatDate(viewingDate))
        .font(.subheadline.bold())

    Button(action: goToNextDate) {
        Image(systemName: "chevron.right")
    }
    .disabled(!hasNextDate)

    Spacer()

    if viewingDate != todayStr {
        Button("Today") {
            switchToToday()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
```

日期列表来源: `GET /api/history` → `archives` 数组

### 7.3 历史日统计

与 Today tab 相同的统计卡片 + Time Breakdown，但数据来自 `GET /api/history/{date}` 。

### 7.4 历史 Turn 列表

与 Live tab 的 Recent Turns 格式一致（精简版 Turn 卡片），但显示该日所有 Turn。

### 7.5 Available Dates 列表

显示所有有归档的日期，点击切换。每行: 日期 + turns 数 + 总时间。

---

## 8. Footer 区 (所有 Tab 通用)

```
┌───────────────────────────────────────────┐
│ [Open Dashboard 🔗]         [⚙ Settings]  │
└───────────────────────────────────────────┘
```

| 按钮 | 动作 |
|------|------|
| Open Dashboard | `NSWorkspace.shared.open(URL(string: "http://localhost:8000")!)` 打开网页版 |
| Settings | 打开 Settings 窗口 (可配置 server 地址等) |

---

## 9. 数据模型 (Swift)

### 9.1 Turn 数据模型

```swift
struct TurnData: Codable, Identifiable {
    let id: String
    let turnNumber: Int
    let startTime: Double
    let totalTime: Double
    let thinkingTime: Double
    let thinkingTokens: Int
    let thinkingTps: Double
    let toolTime: Double
    let toolTimeHook: Double
    let toolTimeRecovered: Double
    let toolCount: Int
    let toolBreakdown: [String: Int]
    let tools: [ToolEntry]
    let outputTime: Double
    let outputChars: Int
    let networkTime: Double
    let unaccountedTime: Double
    let apiCalls: Int
    let projectId: String
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
    var id: String { "\(tool)-\(duration)" }
    let tool: String
    let duration: Double
    let detail: String
}
```

### 9.2 WebSocket 消息模型

```swift
// 服务端发来的消息类型
enum WSMessageType: String, Codable {
    case `init`
    case turnStart = "turn_start"
    case toolStart = "tool_start"
    case toolEnd = "tool_end"
    case turnComplete = "turn_complete"
    case reset
}

struct WSMessage: Codable {
    let type: WSMessageType

    // init
    let turns: [TurnData]?
    let date: String?
    let active: Bool?

    // turn_start
    let turnNumber: Int?       // "turn_number"
    let projectName: String?   // "project_name"
    let ts: Double?

    // tool_start / tool_end
    let tool: String?
    let detail: String?

    // turn_complete
    let data: TurnData?

    enum CodingKeys: String, CodingKey {
        case type, turns, date, active
        case turnNumber = "turn_number"
        case projectName = "project_name"
        case ts, tool, detail, data
    }
}
```

### 9.3 API 响应模型

```swift
// GET /api/turns
struct TurnsResponse: Codable {
    let turns: [TurnData]
    let date: String
}

// GET /api/current
struct CurrentTurnResponse: Codable {
    let active: Bool
    let turnNumber: Int?       // "turn_number"
    let elapsed: Double?
    let toolTime: Double?      // "tool_time"
    let toolCount: Int?        // "tool_count"
    let currentTool: String?   // "current_tool"

    enum CodingKeys: String, CodingKey {
        case active
        case turnNumber = "turn_number"
        case elapsed
        case toolTime = "tool_time"
        case toolCount = "tool_count"
        case currentTool = "current_tool"
    }
}

// GET /api/history
struct HistoryListResponse: Codable {
    let today: String
    let archives: [ArchiveEntry]
}

struct ArchiveEntry: Codable {
    let date: String
    let turns: Int
    let totalTime: Double  // "total_time"

    enum CodingKeys: String, CodingKey {
        case date, turns
        case totalTime = "total_time"
    }
}

// GET /api/history/{date}
struct HistoryDateResponse: Codable {
    let date: String?
    let turns: [TurnData]?
    let error: String?
}
```

### 9.4 App 状态模型

```swift
@MainActor
class MonitorState: ObservableObject {
    // 连接状态
    @Published var isConnected = false
    @Published var reconnectCountdown = 0

    // 今日数据
    @Published var todayStr = ""
    @Published var turns: [TurnData] = []

    // 活跃 Turn
    @Published var activeTurn: ActiveTurnInfo?

    // 历史
    @Published var availableDates: [ArchiveEntry] = []
    @Published var viewingDate = ""          // "" = today
    @Published var historyTurns: [TurnData] = []

    // 计算属性
    var totalTurns: Int { turns.count }
    var totalTime: Double { turns.reduce(0) { $0 + $1.totalTime } }
    var avgTps: Double {
        let valid = turns.filter { $0.thinkingTps > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.thinkingTps } / Double(valid.count)
    }
    var totalThinkingTime: Double { turns.reduce(0) { $0 + $1.thinkingTime } }
    var totalToolTime: Double { turns.reduce(0) { $0 + $1.toolTime } }
    var totalOutputTime: Double { turns.reduce(0) { $0 + $1.outputTime } }
    var totalOtherTime: Double { turns.reduce(0) { $0 + $1.networkTime + $1.unaccountedTime } }

    // 聚合工具统计
    var toolAggregation: [(name: String, count: Int, duration: Double)] { ... }

    // 聚合项目统计
    var projectAggregation: [(name: String, turnCount: Int, totalTime: Double)] { ... }
}

struct ActiveTurnInfo {
    let turnNumber: Int
    let startTime: Date        // 用于本地计时
    var currentTool: String?
    var currentToolDetail: String?
    var projectName: String?
}
```

---

## 10. 网络层

### 10.1 Server 配置

```swift
struct ServerConfig {
    var host: String = "localhost"
    var port: Int = 8000

    var baseURL: String { "http://\(host):\(port)" }
    var wsURL: String { "ws://\(host):\(port)/ws" }
}
```

### 10.2 WebSocket 连接管理

```swift
class WebSocketService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var isIntentionalDisconnect = false
    private let reconnectDelay: TimeInterval = 3.0

    func connect(to url: URL) { ... }
    func disconnect() { ... }
    private func receiveMessage() { ... }
    private func scheduleReconnect() { ... }

    // 回调
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onMessage: ((WSMessage) -> Void)?
}
```

### 10.3 消息处理逻辑

```
收到 init:
  → turns = msg.turns
  → todayStr = msg.date
  → if msg.active → 开始轮询 /api/current

收到 turn_start:
  → activeTurn = ActiveTurnInfo(turnNumber: msg.turnNumber, startTime: now)
  → 启动本地 0.5s 计时器
  → 更新菜单栏文字

收到 tool_start:
  → activeTurn.currentTool = msg.tool
  → activeTurn.currentToolDetail = msg.detail
  → 更新菜单栏文字（显示工具名）

收到 tool_end:
  → activeTurn.currentTool = nil
  → 更新菜单栏文字（恢复为 thinking 状态）

收到 turn_complete:
  → turns.append(msg.data)
  → activeTurn = nil
  → 停止计时器
  → 更新菜单栏文字（回到空闲统计）

收到 reset:
  → turns = []
  → activeTurn = nil
```

### 10.4 HTTP API 调用

| 接口 | 方法 | 用途 |
|------|------|------|
| `/api/turns` | GET | 获取今日 Turn 列表 |
| `/api/current` | GET | 获取活跃 Turn 状态 |
| `/api/history` | GET | 获取可用归档日期列表 |
| `/api/history/{date}` | GET | 获取某日历史数据 |
| `/api/reset` | POST | 重置今日数据 |

---

## 11. 项目结构

```
VibeMonitor/
├── VibeMonitor.xcodeproj
├── VibeMonitor/
│   ├── VibeMonitorApp.swift            # @main 入口
│   ├── AppDelegate.swift               # NSStatusItem + NSPopover 管理
│   │
│   ├── Models/
│   │   ├── TurnData.swift              # Turn 数据模型 (Codable)
│   │   ├── WSMessage.swift             # WebSocket 消息模型
│   │   ├── APIResponses.swift          # HTTP API 响应模型
│   │   └── MonitorState.swift          # App 全局状态 (@Observable)
│   │
│   ├── Services/
│   │   ├── WebSocketService.swift      # WebSocket 连接管理
│   │   ├── APIService.swift            # HTTP API 调用
│   │   └── ServerConfig.swift          # 服务器配置
│   │
│   ├── Views/
│   │   ├── PopoverView.swift           # Popover 主容器 (Header + Tab + Footer)
│   │   ├── LiveView.swift              # Tab1: 实时视图
│   │   ├── TodayView.swift             # Tab2: 今日统计
│   │   ├── HistoryView.swift           # Tab3: 历史视图
│   │   ├── SettingsView.swift          # 设置窗口
│   │   │
│   │   └── Components/
│   │       ├── ActiveTurnCard.swift     # 活跃 Turn 指示卡
│   │       ├── TurnRow.swift            # 精简 Turn 行
│   │       ├── MiniStackBar.swift       # 迷你堆叠条形图
│   │       ├── BreakdownBar.swift       # 时间分解水平条
│   │       ├── StatCard.swift           # 统计小卡片
│   │       ├── ToolTag.swift            # 工具标签
│   │       └── ConnectionBadge.swift    # 连接状态指示
│   │
│   ├── Helpers/
│   │   ├── TimeFormatter.swift         # 时间格式化 (45.1s → "45.1s", 325s → "5m 25s")
│   │   ├── ColorTheme.swift            # 颜色定义 (与网页端一致)
│   │   └── ToolNameFormatter.swift     # 工具名缩短 (shortToolName 逻辑)
│   │
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/
│   │
│   └── Info.plist                      # LSUIElement = YES
│
└── VibeMonitorTests/                   # 可选
```

---

## 12. 颜色定义

与网页端 CSS 变量保持一致：

```swift
// ColorTheme.swift
import SwiftUI

extension Color {
    // 5 个时间分类颜色 (与 script.js COLORS 对象一致)
    static let vmThinking    = Color(hex: "#a78bfa")  // 紫色
    static let vmTool        = Color(hex: "#fbbf24")  // 黄色
    static let vmOutput      = Color(hex: "#38bdf8")  // 蓝色
    static let vmNetwork     = Color(hex: "#fb7185")  // 粉色
    static let vmUnaccounted = Color(hex: "#94a3b8")  // 灰色

    // 项目颜色 (与 script.js PROJECT_COLORS 一致)
    static let vmProjectColors: [Color] = [
        Color(hex: "#818cf8"), Color(hex: "#34d399"),
        Color(hex: "#fb923c"), Color(hex: "#f472b6"),
        Color(hex: "#22d3ee"), Color(hex: "#a78bfa"),
        Color(hex: "#facc15"), Color(hex: "#fb7185"),
    ]

    // 连接状态
    static let vmConnected    = Color(hex: "#34d399")  // 绿
    static let vmDisconnected = Color(hex: "#fb7185")  // 红

    // 背景
    static let vmCardBg = Color(.quaternarySystemFill)
}

// hex 颜色扩展
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
```

---

## 13. 关键交互逻辑

### 13.1 工具名缩短 (与网页端 shortToolName 一致)

```swift
// ToolNameFormatter.swift
func shortToolName(_ name: String) -> String {
    if name.hasPrefix("mcp__") {
        let stripped = name.replacingOccurrences(of: "mcp__", with: "")
        let parts = stripped.components(separatedBy: "__")
        let server = parts[0]
            .replacingOccurrences(of: "Claude_in_Chrome", with: "Chrome")
            .replacingOccurrences(of: "Claude_Preview", with: "Preview")
        if parts.count > 1 {
            return "\(server):\(parts[1...]joined(separator: "_"))"
        }
        return server
    }
    return name
}
```

### 13.2 时间格式化

```swift
// TimeFormatter.swift
func formatTime(_ seconds: Double) -> String {
    if seconds < 60 {
        return String(format: "%.1fs", seconds)
    }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    if m < 60 {
        return "\(m)m \(s)s"
    }
    let h = m / 60
    let rm = m % 60
    return "\(h)h \(rm)m"
}
```

### 13.3 Popover 自动关闭

```swift
// NSPopover.behavior = .transient
// 点击 Popover 外部时自动关闭
popover.behavior = .transient
```

---

## 14. Info.plist 配置

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 不显示 Dock 图标，不出现在 Cmd+Tab -->
    <key>LSUIElement</key>
    <true/>

    <!-- App 名称 -->
    <key>CFBundleName</key>
    <string>Vibe Monitor</string>

    <!-- 最低系统版本 -->
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

---

## 15. 网页端功能 → 菜单栏对照表

完整的功能映射，确保不遗漏：

| # | 网页端功能 | 菜单栏位置 | 实现方式 |
|---|-----------|-----------|---------|
| 1 | 连接状态 badge (Connected/Disconnected) | Header 右侧 + 菜单栏图标颜色 | ConnectionBadge 组件 |
| 2 | Reset 按钮 | Today tab 底部 | Button + 确认 Alert |
| 3 | 日期导航 (◀ Today ▶) | History tab 顶部 | HStack + chevron buttons |
| 4 | "Live" 回到今天按钮 | History tab 日期导航旁 | "Today" button |
| 5 | Active Turn 指示器 (脉冲点 + 编号 + 计时 + 工具) | Live tab 顶部卡片 + 菜单栏文字 | ActiveTurnCard 组件 |
| 6 | 项目筛选 chips | Today tab Projects 区 | 列表行 (不做筛选,只展示) |
| 7 | 统计卡片 (Turns / Time / Avg TPS) | Today tab 顶部 + History tab | StatCard ×3 |
| 8 | 饼图 (Doughnut: Thinking/Tool/Output/Overhead) | Today tab Time Breakdown | 水平条形图 (4行) |
| 9 | 堆叠条形图 (每个 Turn 的时间分解) | Live tab 每个 Turn 行内 | MiniStackBar 组件 |
| 10 | Turn 详情卡片 - 编号 + 总时间 | Turn 行第 1 行 | TurnRow 组件 |
| 11 | Turn 详情卡片 - TPS badge | Turn 行第 1 行 | 紫色小标签 |
| 12 | Turn 详情卡片 - 彩色进度条 | Turn 行第 2 行 | MiniStackBar |
| 13 | Turn 详情卡片 - 分项时间 (Thinking/Tool/Output/Network/Other) | Turn 行第 2 行 (精简为 "think X tool Y") | 文字摘要 |
| 14 | Turn 详情卡片 - 项目 badge | Turn 行（仅多项目时显示） | 小标签 |
| 15 | Turn 详情卡片 - Tool tags (Edit ×2, Bash ×1) | Turn 行第 3 行 | ToolTag 组件 |
| 16 | Turn 详情卡片 - Tool 详细行 (每个工具调用的时间条) | 不在 Popover 显示 | 留给独立窗口 |
| 17 | 历史数据查看 | History tab | 复用 Today 的组件 |

**唯一省略的**: 网页端每个 Turn 卡片内的「Tool 详细行」（每次工具调用的独立时间条和详情），这个在 Popover 里太占空间。保留在 "Open Dashboard" 的网页版中查看。

---

## 16. 启动流程

```
App Launch
  ├── AppDelegate.applicationDidFinishLaunching()
  │   ├── 创建 NSStatusItem (icon + 初始文字 "ready")
  │   ├── 创建 NSPopover (contentSize: 360×520, behavior: .transient)
  │   ├── 设置 PopoverView(state: monitorState) 为 popover 内容
  │   └── 启动 WebSocketService.connect()
  │
  ├── WebSocket 连接成功
  │   ├── isConnected = true
  │   └── 等待 init 消息
  │
  └── 收到 init 消息
      ├── turns = msg.turns
      ├── todayStr = msg.date
      ├── 更新菜单栏文字 (空闲统计)
      ├── if msg.active → 轮询 /api/current 获取活跃 Turn 信息
      └── 调用 /api/history 获取可用日期列表
```

---

## 17. 注意事项

1. **内存**: Popover 关闭后不销毁，保持状态。NSPopover 在 `.transient` 模式下会自动关闭但不销毁 contentViewController。

2. **线程安全**: WebSocket 回调在后台线程，所有 `@Published` 属性更新必须在 `@MainActor` 上。

3. **断线重连**: WebSocket 断开后 3 秒自动重连，指数退避最大 30 秒。

4. **日期切换**: History tab 切换日期时，调用 `/api/history/{date}` 获取数据，不走 WebSocket。

5. **菜单栏文字宽度**: 使用 `.monospacedDigit()` 字体避免数字变化时宽度跳动。

6. **暗色模式**: SwiftUI 原生支持，颜色用 `.opacity()` 而非硬编码 hex+alpha。条形图的颜色用 `Color.vmThinking.opacity(0.7)` 模式。

7. **开机自启**: 可选功能，用 `SMAppService.register()` (macOS 13+) 实现 Login Item。
