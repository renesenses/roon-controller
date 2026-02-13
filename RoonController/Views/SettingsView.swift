import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("uiMode") private var uiMode = "player"
    @AppStorage("appTheme") private var appTheme = "light"
    @State private var coreIP: String = RoonService.savedCoreIP ?? ""

    var body: some View {
        Form {
            Section("Interface") {
                Picker("Mode d'affichage", selection: $uiMode) {
                    Text("Player").tag("player")
                    Text("Roon").tag("roon")
                }
                .pickerStyle(.segmented)

                Text("Player : vue compacte avec pochette centrale. Roon : layout avec barre de transport en bas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Connexion Roon Core") {
                HStack {
                    if roonService.connectionState == .connected {
                        Label("Connecte au Roon Core", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if roonService.connectionState == .connecting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(roonService.connectionDetail ?? "Connexion en cours...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if roonService.connectionState == .waitingForApproval {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("En attente d'approbation dans Roon...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Label("Deconnecte", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Spacer()

                    Button("Reconnecter") {
                        roonService.disconnect()
                        let ip = coreIP.trimmingCharacters(in: .whitespaces)
                        if !ip.isEmpty {
                            roonService.connectCore(ip: ip)
                        } else {
                            roonService.connect()
                        }
                    }
                }

                if let error = roonService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Text("L'application decouvre automatiquement le Roon Core via le protocole SOOD sur le reseau local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Core Roon (connexion manuelle)") {
                TextField("Adresse IP du Core", text: $coreIP)
                Button("Connecter a ce Core") {
                    let ip = coreIP.trimmingCharacters(in: .whitespaces)
                    if !ip.isEmpty {
                        roonService.connectCore(ip: ip)
                    }
                }
                .disabled(coreIP.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Reinitialiser l'autorisation", role: .destructive) {
                    RoonRegistration.clearToken()
                    roonService.disconnect()
                    let ip = coreIP.trimmingCharacters(in: .whitespaces)
                    if !ip.isEmpty {
                        roonService.connectCore(ip: ip)
                    } else {
                        roonService.connect()
                    }
                }
                .font(.caption)

                Text("Efface le token d'autorisation et force un nouvel enregistrement aupres du Core.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 480)
    }
}
