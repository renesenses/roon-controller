import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("uiMode") private var uiMode = "roon"
    @AppStorage("appTheme") private var appTheme = "light"
    @AppStorage("default_zone_name") private var defaultZoneName = ""
    @AppStorage("sidebar_playlist_count") private var sidebarPlaylistCount = 10
    @AppStorage("cache_max_size_mb") private var cacheMaxSizeMB = 0
    @State private var cacheSizeMB: Double = 0
    @State private var coreIP: String = RoonService.savedCoreIP ?? ""

    var body: some View {
        Form {
            Section("Interface") {
                Picker("Default display mode", selection: $uiMode) {
                    Text("Player").tag("player")
                    Text("Roon").tag("roon")
                }
                .pickerStyle(.segmented)

                Text("Player: compact view with centered artwork. Roon: layout with transport bar at the bottom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Playback zone") {
                Picker("Default zone", selection: $defaultZoneName) {
                    Text("Automatic (first zone)").tag("")
                    ForEach(roonService.zones) { zone in
                        Text(zone.display_name).tag(zone.display_name)
                    }
                }

                Text("The selected zone will be used automatically at startup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Playlists in sidebar", selection: $sidebarPlaylistCount) {
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("All").tag(0)
                }

                Text("Number of playlists shown in the sidebar. Search always covers all playlists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if roonService.connectionState == .connected {
                Section("Roon Profile") {
                    if roonService.availableProfiles.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading profiles...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Active profile", selection: Binding<String>(
                            get: { roonService.profileName ?? "" },
                            set: { newName in
                                if let profile = roonService.availableProfiles.first(where: { $0.title == newName }),
                                   let key = profile.item_key {
                                    roonService.switchProfile(itemKey: key)
                                }
                            }
                        )) {
                            ForEach(roonService.availableProfiles) { profile in
                                Text(profile.title ?? "?").tag(profile.title ?? "")
                            }
                        }
                    }

                    Text("The profile determines playback preferences (history, favorites, suggestions).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    roonService.fetchAvailableProfiles()
                }
            }

            Section("Image cache") {
                HStack {
                    Text("Current size")
                    Spacer()
                    Text(formatCacheSize(cacheSizeMB))
                        .foregroundStyle(.secondary)
                }

                Picker("Maximum size", selection: $cacheMaxSizeMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("Unlimited").tag(0)
                }

                Button("Clear cache") {
                    Task {
                        await RoonImageCache.shared.clearAll()
                        let bytes = await RoonImageCache.shared.diskCacheSize()
                        cacheSizeMB = Double(bytes) / 1_000_000
                    }
                }

                Text("Album artwork is cached on disk for faster access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                Task {
                    let bytes = await RoonImageCache.shared.diskCacheSize()
                    cacheSizeMB = Double(bytes) / 1_000_000
                }
            }

            Section("Roon Core Connection") {
                HStack {
                    if roonService.connectionState == .connected {
                        Label("Connected to Roon Core", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if roonService.connectionState == .connecting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(roonService.connectionDetail ?? "Connecting...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if roonService.connectionState == .waitingForApproval {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for approval in Roon...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Label("Disconnected", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Spacer()

                    Button("Reconnect") {
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

                Text("The app automatically discovers the Roon Core via the SOOD protocol on the local network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Roon Core (manual connection)") {
                TextField("Core IP address", text: $coreIP)
                Button("Connect to this Core") {
                    let ip = coreIP.trimmingCharacters(in: .whitespaces)
                    if !ip.isEmpty {
                        roonService.connectCore(ip: ip)
                    }
                }
                .disabled(coreIP.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Reset authorization", role: .destructive) {
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

                Text("Clears the authorization token and forces a new registration with the Core.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .groupedFormStyleCompat()
        .frame(width: 450)
        .frame(minHeight: 500, idealHeight: 620)
    }

    private func formatCacheSize(_ mb: Double) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        } else {
            return "\(Int(mb)) MB"
        }
    }
}
