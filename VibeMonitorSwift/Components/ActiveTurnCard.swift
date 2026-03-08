import SwiftUI

struct ActiveTurnCard: View {
    let turn: Int
    let elapsed: Double
    let currentTool: String?
    let detail: String?

    @State private var pulse = 1.0

    private var phase: String {
        if let tool = currentTool {
            return "Running: \(shortToolName(tool))"
        }
        return "Thinking..."
    }

    private var phaseColor: Color {
        currentTool == nil ? .vmThinking : .vmTool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Pulse dot + Turn number + Elapsed
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulse)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                            pulse = 0.3
                        }
                    }

                Text("Turn #\(turn)")
                    .font(.subheadline.bold())

                Spacer()

                Text(String(format: "%.1fs", elapsed))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Row 2: Phase + Tool detail
            VStack(alignment: .leading, spacing: 3) {
                Text(phase)
                    .font(.caption)
                    .foregroundStyle(phaseColor)

                if let detail = detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Row 3: Indeterminate progress
            ProgressView()
                .progressViewStyle(.linear)
                .tint(phaseColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.vmThinking.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.vmThinking.opacity(0.2), lineWidth: 1)
        )
    }
}
