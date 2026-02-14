import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("uiMode") private var uiMode = "roon"
    @AppStorage("appTheme") private var appTheme = "light"
    @AppStorage("default_zone_name") private var defaultZoneName = ""
    @AppStorage("sidebar_playlist_count") private var sidebarPlaylistCount = 10
    @State private var coreIP: String = RoonService.savedCoreIP ?? ""

    var body: some View {
        Form {
            Section("Interface") {
                Picker("Mode d'affichage par défaut", selection: $uiMode) {
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

            Section("Zone de lecture") {
                Picker("Zone par défaut", selection: $defaultZoneName) {
                    Text("Automatique (première zone)").tag("")
                    ForEach(roonService.zones) { zone in
                        Text(zone.display_name).tag(zone.display_name)
                    }
                }

                Text("La zone sélectionnée sera utilisée automatiquement au démarrage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Playlists dans la sidebar", selection: $sidebarPlaylistCount) {
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("Toutes").tag(0)
                }

                Text("Nombre de playlists affichées dans la sidebar. La recherche porte toujours sur la totalité.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                Button("Réinitialiser l'autorisation", role: .destructive) {
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

                Text("Efface le token d'autorisation et force un nouvel enregistrement auprès du Core.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .frame(minHeight: 500, idealHeight: 620)
    }
}
