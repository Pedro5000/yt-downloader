import SwiftUI
import AVKit
import AVFoundation

/// Compressor-style clip preview: plays a low-res proxy stream and lets the user set
/// in/out points on a timeline with draggable handles. On apply, the points are written
/// back as clip start/end (which drive yt-dlp's --download-sections at download time).
struct ClipPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    let sourceURL: String
    let duration: Double
    let cookiesBrowser: String?
    let onApply: (_ start: Double, _ end: Double) -> Void

    @State private var player = AVPlayer()
    @State private var loading = true
    @State private var failed = false
    @State private var current: Double = 0
    @State private var start: Double
    @State private var end: Double
    @State private var isPlaying = false
    @State private var timeObserver: Any?

    init(sourceURL: String, duration: Double, start: Double, end: Double,
         cookiesBrowser: String?, onApply: @escaping (Double, Double) -> Void) {
        self.sourceURL = sourceURL
        self.duration = max(duration, 0)
        self.cookiesBrowser = cookiesBrowser
        self.onApply = onApply
        _start = State(initialValue: max(0, start))
        _end = State(initialValue: end > start ? min(end, max(duration, 0.1)) : max(duration, 0.1))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(app.tr("Découper l'extrait", "Trim clip"))
                .font(.rounded(18, .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black)
                if loading {
                    ProgressView().controlSize(.large).tint(.white)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "play.slash").font(.system(size: 34)).foregroundStyle(.white.opacity(0.4))
                        Text(app.tr("Aperçu indisponible pour cette vidéo.", "Preview unavailable for this video."))
                            .font(.rounded(12)).foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    PlayerSurface(player: player).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: 640, height: 360)

            if !loading && !failed {
                HStack(spacing: 12) {
                    Button { togglePlay() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
                    }
                    .buttonStyle(GhostButtonStyle())
                    Text(Formatting.duration(current)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(Formatting.duration(start)) – \(Formatting.duration(end))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                }
                TrimTimeline(duration: duration, current: $current, start: $start, end: $end) { seek($0) }
                    .frame(height: 30)
            }

            HStack {
                Button(app.tr("Annuler", "Cancel")) { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button(app.tr("Appliquer l'extrait", "Apply clip")) {
                    onApply(start, end); dismiss()
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(loading || failed || end <= start)
            }
        }
        .padding(22)
        .frame(width: 684)
        .background(Theme.appBackground)
        .task { await load() }
        .onDisappear { cleanup() }
    }

    private func load() async {
        let url = await YTDLPService.previewURL(url: sourceURL, cookiesBrowser: cookiesBrowser)
        loading = false
        guard let url else { failed = true; return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = false
        seek(start)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { time in
            let t = time.seconds
            if t.isFinite { current = t }
            if isPlaying && current >= end { player.pause(); isPlaying = false }
        }
    }

    private func togglePlay() {
        if isPlaying { player.pause(); isPlaying = false }
        else {
            if current < start || current >= end { seek(start) }
            player.play(); isPlaying = true
        }
    }

    private func seek(_ t: Double) {
        current = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func cleanup() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
    }
}

/// Bare AVPlayer video surface (no native transport — we drive playback ourselves).
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}

/// Timeline with a playhead and two draggable in/out handles; the selection is highlighted.
private struct TrimTimeline: View {
    let duration: Double
    @Binding var current: Double
    @Binding var start: Double
    @Binding var end: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Seek surface (behind everything).
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { onSeek(time($0.location.x, w)) })

                Capsule().fill(Color.white.opacity(0.12)).frame(height: 6).allowsHitTesting(false)
                Rectangle().fill(Theme.accent.opacity(0.45))
                    .frame(width: max(0, x(end, w) - x(start, w)), height: 6)
                    .offset(x: x(start, w)).allowsHitTesting(false)
                Rectangle().fill(.white).frame(width: 2, height: 22)
                    .offset(x: x(current, w) - 1).allowsHitTesting(false)

                handle.offset(x: x(start, w) - 7)
                    .gesture(DragGesture(minimumDistance: 0).onChanged {
                        start = min(end - 0.5, time($0.location.x, w))
                    })
                handle.offset(x: x(end, w) - 7)
                    .gesture(DragGesture(minimumDistance: 0).onChanged {
                        end = max(start + 0.5, time($0.location.x, w))
                    })
            }
        }
    }

    private func x(_ t: Double, _ w: CGFloat) -> CGFloat { duration > 0 ? CGFloat(t / duration) * w : 0 }
    private func time(_ px: CGFloat, _ w: CGFloat) -> Double {
        duration > 0 ? max(0, min(duration, Double(px / w) * duration)) : 0
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.accent)
            .frame(width: 14, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}
