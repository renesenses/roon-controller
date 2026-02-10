import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("backendHost") private var backendHost: String = "localhost"
    @AppStorage("backendPort") private var backendPort: Int = 3333
    @State private var coreIP: String = ""

    var body: some View {
        Form {
            Section("Backend Node.js") {
                TextField("Hôte", text: $backendHost)
                TextField("Port", value: $backendPort, format: .number)

                HStack {
                    Button("Appliquer et reconnecter") {
                        roonService.backendHost = backendHost
                        roonService.backendPort = backendPort
                        roonService.disconnect()
                        roonService.connect()
                    }

                    if roonService.connectionState == .connected {
                        Label("Connecté", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if roonService.connectionState == .connecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Core Roon (connexion manuelle)") {
                TextField("Adresse IP du Core", text: $coreIP)
                Button("Connecter à ce Core") {
                    let ip = coreIP.trimmingCharacters(in: .whitespaces)
                    if !ip.isEmpty {
                        roonService.connectCore(ip: ip)
                    }
                }
                .disabled(coreIP.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("Le backend essaie automatiquement de découvrir le Core Roon via SOOD. Utilisez ce champ uniquement si la découverte automatique échoue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
        .onAppear {
            backendHost = roonService.backendHost
            backendPort = roonService.backendPort
        }
    }
}
