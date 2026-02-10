import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var roonService: RoonService
    @State private var coreIP: String = ""

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

                Text("Recherche du Roon Core sur le reseau local via SOOD...")
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
                                .tint(Color.roonSecondary)
                            Text("Connexion au Roon Core...")
                                .foregroundStyle(Color.roonSecondary)
                        }
                    case .disconnected:
                        Label("Deconnecte du Roon Core", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    case .connected:
                        Label("Connecte — en attente des zones...", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }

                Divider()
                    .overlay(Color.roonTertiary.opacity(0.3))
                    .frame(maxWidth: 300)

                VStack(spacing: 12) {
                    Text("Connexion manuelle au Core Roon (optionnel)")
                        .font(.headline)
                        .foregroundStyle(Color.roonText)

                    HStack {
                        TextField("Adresse IP du Core", text: $coreIP)
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

                        Button("Connecter") {
                            let ip = coreIP.trimmingCharacters(in: .whitespaces)
                            if !ip.isEmpty {
                                roonService.connectCore(ip: ip)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.roonAccent)
                        .disabled(coreIP.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Button("Reconnecter") {
                    roonService.disconnect()
                    roonService.connect()
                }
                .buttonStyle(.bordered)
                .tint(Color.roonAccent)

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
