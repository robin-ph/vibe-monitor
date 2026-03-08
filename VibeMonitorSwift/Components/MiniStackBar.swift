import SwiftUI

struct MiniStackBar: View {
    let thinking: Double
    let tool: Double
    let output: Double
    let network: Double
    let other: Double
    let total: Double

    var body: some View {
        GeometryReader { geo in
            let safeTotal = max(total, 1)
            HStack(spacing: 0) {
                if thinking > 0 {
                    Rectangle()
                        .fill(Color.vmThinking.opacity(0.8))
                        .frame(width: geo.size.width * (thinking / safeTotal))
                }
                if tool > 0 {
                    Rectangle()
                        .fill(Color.vmTool.opacity(0.8))
                        .frame(width: geo.size.width * (tool / safeTotal))
                }
                if output > 0 {
                    Rectangle()
                        .fill(Color.vmOutput.opacity(0.8))
                        .frame(width: geo.size.width * (output / safeTotal))
                }
                if network > 0 {
                    Rectangle()
                        .fill(Color.vmNetwork.opacity(0.8))
                        .frame(width: geo.size.width * (network / safeTotal))
                }
                if other > 0 {
                    Rectangle()
                        .fill(Color.vmUnaccounted.opacity(0.8))
                        .frame(width: geo.size.width * (other / safeTotal))
                }
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
