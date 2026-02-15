import SwiftUI

struct RoonKaraokeView: View {
    @EnvironmentObject var roonService: RoonService

    @State private var lyricsResult: LyricsResult = .notFound
    @State private var isLoading = false
    @State private var lastTrackIdentity = ""

    private var currentLineIndex: Int? {
        guard case .synced(let lines) = lyricsResult else { return nil }
        return LyricsService.currentLineIndex(lines: lines, seekPosition: roonService.seekPosition)
    }

    private func artImageKey(for np: NowPlaying) -> String? {
        roonService.resolvedImageKey(for: np)
    }

    var body: some View {
        ZStack {
            if let zone = roonService.currentZone, let np = zone.now_playing {
                blurredBackground(imageKey: artImageKey(for: np))
                lyricsContent(nowPlaying: np)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.roonBackground, ignoresSafeAreaEdges: [])
        .onChange(of: trackIdentity) { _, newValue in
            if newValue != lastTrackIdentity {
                lastTrackIdentity = newValue
                Task { await loadLyrics() }
            }
        }
        .onAppear {
            let identity = trackIdentity
            if identity != lastTrackIdentity {
                lastTrackIdentity = identity
                Task { await loadLyrics() }
            }
        }
    }

    // MARK: - Track Identity

    private var trackIdentity: String {
        guard let np = roonService.currentZone?.now_playing else { return "" }
        return roonService.trackIdentity(np)
    }

    // MARK: - Load Lyrics

    private func loadLyrics() async {
        guard let np = roonService.currentZone?.now_playing,
              let info = np.three_line else {
            lyricsResult = .notFound
            return
        }

        let title = info.line1 ?? ""
        let artist = info.line2 ?? ""
        let album = info.line3 ?? ""
        let duration = np.length ?? 0

        guard !title.isEmpty else {
            lyricsResult = .notFound
            return
        }

        isLoading = true
        let result = await LyricsService.shared.fetchLyrics(
            title: title, artist: artist, album: album, duration: duration
        )
        isLoading = false
        lyricsResult = result
    }

    // MARK: - Blurred Background

    @ViewBuilder
    private func blurredBackground(imageKey: String?) -> some View {
        if let url = roonService.imageURL(key: imageKey, width: 600, height: 600) {
            GeometryReader { geo in
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 100)
                            .opacity(0.25)
                    }
                }
                .id(imageKey)
                .transition(.opacity)
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(Color.roonBackground.opacity(0.65))
            }
        }
    }

    // MARK: - Lyrics Content

    private func lyricsContent(nowPlaying: NowPlaying) -> some View {
        VStack(spacing: 0) {
            // Header with track info
            header(nowPlaying: nowPlaying)

            // Lyrics area
            if isLoading {
                loadingState
            } else {
                switch lyricsResult {
                case .synced(let lines):
                    syncedLyricsView(lines: lines)
                case .plain(let text):
                    plainLyricsView(text: text)
                case .instrumental:
                    instrumentalState
                case .notFound:
                    notFoundState
                }
            }
        }
    }

    // MARK: - Header

    private func header(nowPlaying: NowPlaying) -> some View {
        HStack(spacing: 16) {
            // Album art thumbnail
            if let url = roonService.imageURL(key: artImageKey(for: nowPlaying), width: 120, height: 120) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.roonPanel
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.three_line?.line1 ?? "")
                    .font(.latoBold(15))
                    .foregroundStyle(Color.roonText)
                    .lineLimit(1)
                if let artist = nowPlaying.three_line?.line2, !artist.isEmpty {
                    Text(artist)
                        .font(.lato(13))
                        .foregroundStyle(Color.roonSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.roonAccent)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Synced Lyrics

    private func syncedLyricsView(lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Spacer().frame(height: 40)

                    ForEach(lines) { line in
                        let isCurrent = currentLineIndex.map { lines[$0].id == line.id } ?? false
                        let isPast = currentLineIndex.map { line.id < lines[$0].id } ?? false

                        if line.text.isEmpty {
                            // Instrumental break — small spacing
                            Spacer().frame(height: 8)
                                .id(line.id)
                        } else {
                            Text(line.text)
                                .font(isCurrent ? .grifoM(32) : .grifoM(24))
                                .foregroundStyle(Color.roonText)
                                .opacity(isCurrent ? 1.0 : (isPast ? 0.4 : 0.6))
                                .scaleEffect(isCurrent ? 1.05 : 1.0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 48)
                                .id(line.id)
                                .animation(.easeInOut(duration: 0.3), value: isCurrent)
                        }
                    }

                    Spacer().frame(height: 120)
                }
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                guard let index = newIndex else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lines[index].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Plain Lyrics

    private func plainLyricsView(text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 40)

                Text(text)
                    .font(.grifoM(20))
                    .foregroundStyle(Color.roonText.opacity(0.8))
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48)

                Spacer().frame(height: 120)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.roonSecondary)
            Text("Recherche des paroles...")
                .font(.lato(15))
                .foregroundStyle(Color.roonSecondary)
            Spacer()
        }
    }

    private var instrumentalState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pianokeys")
                .font(.system(size: 48))
                .foregroundStyle(Color.roonTertiary)
            Text("Morceau instrumental")
                .font(.grifoM(24))
                .foregroundStyle(Color.roonSecondary)
            Spacer()
        }
    }

    private var notFoundState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.page.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.roonTertiary)
            Text("Paroles non disponibles")
                .font(.grifoM(24))
                .foregroundStyle(Color.roonSecondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.roonTertiary)
            Text("Rien en lecture")
                .font(.inter(24))
                .foregroundStyle(Color.roonSecondary)
        }
    }
}
