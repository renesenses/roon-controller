import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var roonService: RoonService
    @State private var coreIP: String = RoonService.savedCoreIP ?? ""

    var body: some View {
        ZStack {
            Color.roonBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "hifispeaker.2")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.roonTertiary)

                Text("Roon Controller")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.roonText)

                Text("Searching for Roon Core on the local network via SOOD...")
                    .foregroundStyle(Color.roonSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                // Connection state indicator
                Group {
                    switch roonService.connectionState {
                    case .connecting:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .accentColor(Color.roonSecondary)
                            Text("Connecting to Roon Core...")
                                .foregroundStyle(Color.roonSecondary)
                        }
                    case .waitingForApproval:
                        VStack(spacing: 12) {
                            Label("Roon Core found", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .accentColor(Color.roonAccent)
                                Text("Waiting for approval...")
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.roonAccent)
                            }
                            VStack(spacing: 6) {
                                Text("The extension must be authorized in Roon Core.")
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.roonText)
                                Text("Open Roon > Settings > Extensions,\nthen enable \"Roon Controller\".")
                                    .foregroundStyle(Color.roonSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .font(.caption)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.roonAccent.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.roonAccent.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                        }
                    case .disconnected:
                        Label("Disconnected from Roon Core", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    case .connected:
                        Label("Connected — waiting for zones...", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }

                Divider()
                    .overlay(Color.roonTertiary.opacity(0.3))
                    .frame(maxWidth: 300)

                VStack(spacing: 12) {
                    Text("Manual connection to Roon Core (optional)")
                        .font(.headline)
                        .foregroundStyle(Color.roonText)

                    HStack {
                        TextField("Core IP address", text: $coreIP)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.roonSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.roonTertiary.opacity(0.4), lineWidth: 0.5)
                                    )
                            )
                            .frame(width: 200)

                        Button("Connect") {
                            let ip = coreIP.trimmingCharacters(in: .whitespaces)
                            if !ip.isEmpty {
                                roonService.connectCore(ip: ip)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accentColor(Color.roonAccent)
                        .disabled(coreIP.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Button("Reconnect") {
                    roonService.disconnect()
                    let ip = coreIP.trimmingCharacters(in: .whitespaces)
                    if !ip.isEmpty {
                        roonService.connectCore(ip: ip)
                    } else {
                        roonService.connect()
                    }
                }
                .buttonStyle(.bordered)
                .accentColor(Color.roonAccent)

                if let error = roonService.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
