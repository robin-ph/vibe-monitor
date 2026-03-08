import SwiftUI

// MARK: - Stat Card

struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.vmCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Breakdown Row

struct BreakdownRow: View {
    let label: String
    let value: Double
    let total: Double
    let color: Color

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return value / total
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.7))
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: 6)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}
