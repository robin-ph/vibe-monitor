import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: MonitorState
    @Binding var isPresented: Bool
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Server Config
            VStack(alignment: .leading, spacing: 10) {
                Text("Server Connection")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Host").font(.caption).frame(width: 40, alignment: .leading)
                    TextField("localhost", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }
                HStack {
                    Text("Port").font(.caption).frame(width: 40, alignment: .leading)
                    TextField("8000", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isConnected ? Color.vmConnected : Color.vmDisconnected)
                        .frame(width: 7, height: 7)
                    Text(state.isConnected ? "Connected to \(state.serverHost):\(state.serverPort)" : "Disconnected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Save Button
            HStack {
                Button("Save & Reconnect") {
                    state.serverHost = host.isEmpty ? "localhost" : host
                    state.serverPort = Int(port) ?? 8000
                    state.disconnect()
                    state.connect()
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if saved {
                    Text("Saved!")
                        .font(.caption)
                        .foregroundColor(Color.vmConnected)
                }
            }

            Divider()

            // About
            HStack {
                Text("Vibe Monitor")
                    .font(.caption.bold())
                Spacer()
                Text("v1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            host = state.serverHost
            port = "\(state.serverPort)"
        }
    }
}
