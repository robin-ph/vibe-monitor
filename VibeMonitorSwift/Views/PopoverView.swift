import SwiftUI

enum ViewTab: Int {
    case live = 0
    case stats = 1  // merged Today + History
}

struct PopoverView: View {
    @ObservedObject var state: MonitorState
    @State private var selectedTab: ViewTab = .live
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(Color.vmThinking)
                    Text("Vibe Monitor").bold()
                }
                Spacer()
                ConnectionBadge(isConnected: state.isConnected)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // MARK: Tab Bar (2 tabs: Live / Stats)
            Picker("", selection: $selectedTab) {
                Text("Live").tag(ViewTab.live)
                Text("Stats").tag(ViewTab.stats)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // MARK: Tab Content
            Group {
                switch selectedTab {
                case .live:
                    LiveView(state: state)
                case .stats:
                    StatsView(state: state)
                }
            }
            .frame(minHeight: 380, maxHeight: 440)

            Divider()

            // MARK: Footer
            HStack {
                Button {
                    if let url = URL(string: state.baseURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Dashboard", systemImage: "safari")
                }

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
        .sheet(isPresented: $showSettings) {
            SettingsView(state: state, isPresented: $showSettings)
        }
    }
}

// MARK: - Connection Badge

struct ConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.vmConnected : Color.vmDisconnected)
                .frame(width: 7, height: 7)
            Text(isConnected ? "Connected" : "Offline")
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isConnected ? Color.vmConnected : Color.vmDisconnected).opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Visual Effect Background

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
