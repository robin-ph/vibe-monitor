import SwiftUI

/// Merged Today + History view. Shows today by default with date navigation to browse history.
struct StatsView: View {
    @ObservedObject var state: MonitorState
    @State private var selectedDate: String = ""
    @State private var showResetConfirm = false

    // MARK: - Date Navigation

    private var allDates: [String] {
        var dates = [state.todayStr]
        dates.append(contentsOf: state.availableDates.map(\.date))
        var seen = Set<String>()
        return dates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var currentIndex: Int {
        allDates.firstIndex(of: effectiveDate) ?? 0
    }

    private var effectiveDate: String {
        (selectedDate.isEmpty ? state.todayStr : selectedDate)
    }

    private var hasPrev: Bool { currentIndex < allDates.count - 1 }
    private var hasNext: Bool { currentIndex > 0 }
    private var isToday: Bool { selectedDate.isEmpty || selectedDate == state.todayStr }

    private var displayTurns: [TurnData] {
        isToday ? state.turns : state.historyTurns
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Date Navigation Bar
            HStack(spacing: 10) {
                Button {
                    guard hasPrev else { return }
                    let newDate = allDates[currentIndex + 1]
                    selectedDate = newDate
                    if newDate != state.todayStr {
                        state.fetchHistoryForDate(newDate)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!hasPrev)
                .buttonStyle(.plain)

                Spacer()

                if isToday {
                    Text("Today \u{00B7} \(formatDateFull(state.todayStr))")
                        .font(.subheadline.bold())
                } else {
                    Text(formatDateFull(selectedDate))
                        .font(.subheadline.bold())
                        .foregroundColor(Color.vmThinking)
                }

                Spacer()

                Button {
                    guard hasNext else { return }
                    let newDate = allDates[currentIndex - 1]
                    if newDate == state.todayStr {
                        selectedDate = ""
                    } else {
                        selectedDate = newDate
                        state.fetchHistoryForDate(newDate)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!hasNext || isToday)
                .buttonStyle(.plain)

                if !isToday {
                    Button("Today") { selectedDate = "" }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider()

            // MARK: Content
            ScrollView {
                if state.isLoadingHistory && !isToday {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else if displayTurns.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.title2)
                        Text("No data for this date")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        // MARK: Stat Cards
                        let stats = MonitorState.computeStats(from: displayTurns)
                        HStack(spacing: 10) {
                            StatCard(label: "Turns", value: "\(displayTurns.count)", color: .vmThinking)
                            StatCard(label: "Time", value: formatTime(stats.totalTime), color: .vmTool)
                            let avgStr = stats.avgTps > 0 ? "\(Int(stats.avgTps))" : "-"
                            StatCard(label: "Avg t/s", value: avgStr, color: .vmOutput)
                        }

                        // MARK: Time Breakdown
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time Breakdown")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)

                            BreakdownRow(label: "Thinking", value: stats.thinkingTime, total: stats.totalTime, color: .vmThinking)
                            BreakdownRow(label: "Tool Use", value: stats.toolTime, total: stats.totalTime, color: .vmTool)
                            BreakdownRow(label: "Output", value: stats.outputTime, total: stats.totalTime, color: .vmOutput)
                            BreakdownRow(label: "Network", value: stats.networkTime, total: stats.totalTime, color: .vmNetwork)
                            BreakdownRow(label: "Other", value: stats.otherTime, total: stats.totalTime, color: .vmUnaccounted)
                        }

                        // MARK: Projects (today only)
                        if isToday && state.projectAggregation.count > 1 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Projects")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)

                                let allNames = state.projectAggregation.map(\.name)
                                ForEach(state.projectAggregation, id: \.name) { project in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(projectColor(for: project.name, allNames: allNames))
                                            .frame(width: 8, height: 8)
                                        Text(project.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(project.turnCount) turns")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(formatTime(project.totalTime))
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                            }
                        }

                        // MARK: Top Tools (today only)
                        if isToday && !state.toolAggregation.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Top Tools")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)

                                let maxDur = state.toolAggregation.first?.duration ?? 1
                                ForEach(state.toolAggregation.prefix(6), id: \.name) { tool in
                                    HStack(spacing: 8) {
                                        Text(shortToolName(tool.name))
                                            .font(.caption)
                                            .frame(width: 72, alignment: .leading)
                                            .lineLimit(1)
                                        Text("\(tool.count)x")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, alignment: .trailing)
                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.vmTool.opacity(0.6))
                                                .frame(width: geo.size.width * (tool.duration / max(maxDur, 1)))
                                        }
                                        .frame(height: 6)
                                        Text(formatTime(tool.duration))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 46, alignment: .trailing)
                                    }
                                }
                            }
                        }

                        // MARK: Turn List (for history dates)
                        if !isToday {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Turns")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)

                                ForEach(displayTurns.reversed()) { turn in
                                    TurnRowView(data: turn)
                                    Divider().opacity(0.3)
                                }
                            }
                        }

                        // MARK: Reset (today only)
                        if isToday {
                            Button(role: .destructive) {
                                showResetConfirm = true
                            } label: {
                                Label("Reset Today", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .alert("Reset Today's Data?", isPresented: $showResetConfirm) {
                                Button("Cancel", role: .cancel) {}
                                Button("Reset", role: .destructive) { state.resetToday() }
                            } message: {
                                Text("This will clear all turn data for today. This cannot be undone.")
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            if selectedDate.isEmpty {
                selectedDate = state.todayStr
            }
        }
    }
}
