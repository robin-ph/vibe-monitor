import SwiftUI

struct LiveView: View {
    @ObservedObject var state: MonitorState
    @State private var currentTime = Date()

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Active Turn Card
                if let active = state.activeTurn {
                    let elapsed = currentTime.timeIntervalSince(active.startTime)
                    ActiveTurnCard(
                        turn: active.turnNumber,
                        elapsed: elapsed,
                        currentTool: active.currentTool,
                        detail: active.currentToolDetail
                    )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "zzz")
                            .font(.caption)
                        Text("Idle — waiting for next turn")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }

                // MARK: Bar Legend
                BarLegend()

                // MARK: Recent Turns
                if !state.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Turns")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        let recentTurns = Array(state.turns.suffix(10).reversed())
                        ForEach(recentTurns) { turn in
                            TurnRowView(data: turn)
                            if turn.id != recentTurns.last?.id {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2)
                        Text("No turns recorded yet")
                            .font(.caption)
                        Text("Start a conversation in Claude Code")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
                }
            }
            .padding(16)
        }
        .onReceive(timer) { _ in
            if state.activeTurn != nil {
                currentTime = Date()
            }
        }
    }
}

// MARK: - Bar Color Legend

struct BarLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(color: .vmThinking, label: "Thinking")
            legendItem(color: .vmTool, label: "Tool")
            legendItem(color: .vmOutput, label: "Output")
            legendItem(color: .vmNetwork, label: "Network")
            legendItem(color: .vmUnaccounted, label: "Other")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color.opacity(0.8))
                .frame(width: 10, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
