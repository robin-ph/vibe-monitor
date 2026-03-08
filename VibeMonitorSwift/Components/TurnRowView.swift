import SwiftUI

struct TurnRowView: View {
    let data: TurnData

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: Turn number + TPS badge + Total time
            HStack(spacing: 6) {
                Text("T\(data.turnNumber)")
                    .font(.caption.bold())
                    .foregroundColor(Color.vmThinking)

                if data.thinkingTps > 0 {
                    Text("\(Int(data.thinkingTps)) t/s")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.vmThinking.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundColor(Color.vmThinking)
                }

                Spacer()

                Text(String(format: "%.1fs", data.totalTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Row 2: Mini stack bar + time summary
            HStack(spacing: 8) {
                MiniStackBar(
                    thinking: data.thinkingTime,
                    tool: data.toolTime,
                    output: data.outputTime,
                    network: data.networkTime,
                    other: data.unaccountedTime,
                    total: data.totalTime
                )

                Text("think \(String(format: "%.1f", data.thinkingTime))  tool \(String(format: "%.1f", data.toolTime))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            // Row 3: Tool tags with counts
            if !data.toolBreakdown.isEmpty {
                let sorted = data.toolBreakdown.sorted { $0.value > $1.value }
                HStack(spacing: 4) {
                    ForEach(sorted.prefix(5), id: \.key) { tool, count in
                        HStack(spacing: 2) {
                            Text(shortToolName(tool))
                            if count > 1 {
                                Text("\u{00D7}\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.vmTool.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }

                    let remaining = data.toolBreakdown.count - 5
                    if remaining > 0 {
                        Text("+\(remaining)")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
