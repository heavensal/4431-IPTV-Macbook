import SwiftUI
import VLCKit

private final class VideoSession: ObservableObject { let player = VLCMediaPlayer() }

struct MediaTrack: Identifiable, Equatable {
    let id: Int32
    let name: String
    static func list(_ ids: [Any], _ names: [Any]) -> [Self] {
        var seen = Set<Int32>()
        return ids.enumerated().compactMap { i, value in
            guard let id = (value as? NSNumber)?.int32Value, seen.insert(id).inserted else { return nil }
            let name = names.indices.contains(i) ? names[i] as? String : nil
            return Self(id:id,name:id == -1 ? "Désactivés" : name ?? "Piste " + String(id))
        }
    }
}
struct EmbeddedVideo: View {
    let url: URL
    let full: Bool
    let toggleScreen: () -> Void
    @StateObject private var session = VideoSession()
    private var engine: VLCMediaPlayer { session.player }
    @State private var position: Double = 0
    @State private var dragging = false
    @State private var seekable = false
    @State private var playing = false
    @State private var failed = false
    @State private var audio = [MediaTrack]()
    @State private var subtitles = [MediaTrack]()
    @State private var audioID: Int32 = -1
    @State private var subtitleID: Int32 = -1
    private func trackMenu(_ label: String, _ tracks: [MediaTrack], _ active: Int32, select: @escaping (Int32)->Void) -> some View {
        Menu {
            if tracks.isEmpty { Text("Aucune piste disponible") }
            ForEach(tracks) { track in
                Button { select(track.id) } label: {
                    if track.id == active { Label(track.name,systemImage:"checkmark") } else { Text(track.name) }
                }
            }
        } label: { Label(label,systemImage:label == "Audio" ? "speaker.wave.2" : "captions.bubble") }.fixedSize()
    }
    var body: some View {
        ZStack(alignment:.bottom) {
            VLCDisplay(engine:engine,url:url)
            if failed { Text("Le moteur VLC ne peut pas lire ce flux.").foregroundStyle(.red) }
            VStack(spacing:3) {
                HStack(spacing:8) {
                Button {
                    if engine.isPlaying { engine.pause() } else { engine.play() }
                } label: { Label(playing ? "Pause" : "Lire",systemImage:playing ? "pause.fill" : "play.fill") }
                trackMenu("Audio",audio,audioID) { engine.currentAudioTrackIndex = $0; audioID = $0 }
                trackMenu("Sous-titres",subtitles,subtitleID) { engine.currentVideoSubTitleIndex = $0; subtitleID = $0 }
                Button(action:toggleScreen) { Label(full ? "Écran ¼" : "Plein écran",systemImage:full ? "rectangle.inset.bottomtrailing" : "arrow.up.left.and.arrow.down.right") }
                }.controlSize(full ? .large : .regular)
                Slider(value:$position,in:0...1,onEditingChanged:{ editing in
                    dragging = editing
                    if !editing && engine.isSeekable { engine.position = Float(position) }
                }).disabled(!seekable)
            }.padding(8).background(Color(red:0.07,green:0.09,blue:0.2).opacity(0.90))
        }.task {
            while !Task.isCancelled {
                audio = MediaTrack.list(engine.audioTrackIndexes,engine.audioTrackNames)
                subtitles = MediaTrack.list(engine.videoSubTitlesIndexes,engine.videoSubTitlesNames)
                audioID = engine.currentAudioTrackIndex
                subtitleID = engine.currentVideoSubTitleIndex
                playing = engine.isPlaying
                seekable = engine.isSeekable
                failed = engine.state == .error
                if !dragging { position = min(1,max(0,Double(engine.position))) }
                do { try await Task.sleep(nanoseconds:500_000_000) } catch { break }
            }
        }
    }
}
private struct VLCDisplay: NSViewRepresentable {
    let engine: VLCMediaPlayer
    let url: URL
    func makeCoordinator() -> VLCMediaPlayer { engine }
    func makeNSView(context:Context) -> VLCVideoView {
        let view = VLCVideoView()
        engine.drawable = view
        engine.media = VLCMedia(url:url)
        engine.play()
        return view
    }
    func updateNSView(_ view:VLCVideoView,context:Context) {}
    static func dismantleNSView(_ view:VLCVideoView, coordinator:VLCMediaPlayer) {
        coordinator.stop()
        coordinator.drawable = nil
        coordinator.media = nil
    }
}
