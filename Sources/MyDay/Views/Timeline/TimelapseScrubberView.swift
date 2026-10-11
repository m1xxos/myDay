import Foundation
import SwiftUI
import AVFoundation
import AVKit
import AppKit

// MARK: - Native AppKit Player View (Crash-free, avoids _AVKit_SwiftUI bug)

public struct NativePlayerView: NSViewRepresentable {
    public let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.showsSharingServiceButton = true
        playerView.showsFrameSteppingButtons = true
        return playerView
    }

    public func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player != player {
            nsView.player = player
        }
    }
}

@MainActor
public final class ScrubberViewModel: ObservableObject {
    @Published public var frames: [URL] = []
    @Published public var currentFrameIndex: Int = 0 {
        didSet {
            updateCurrentImage()
        }
    }
    @Published public var isHovering: Bool = false
    @Published public var isGeneratingVideo: Bool = false
    @Published public var player: AVPlayer? = nil
    @Published public var showVideoModal: Bool = false
    @Published public var currentImage: NSImage? = nil

    private var imageCache: [Int: NSImage] = [:]

    public init() {}

    public func loadFrames(for card: TimelineCard) {
        guard frames.isEmpty else { return } // Prevent reloading if already loaded
        
        let loaded = TimelapseStorage.shared.getFrames(between: card.startTime, and: card.endTime)
        if !loaded.isEmpty {
            self.frames = loaded
            self.currentFrameIndex = loaded.count / 2
        } else if let keyframe = card.keyframePath, FileManager.default.fileExists(atPath: keyframe) {
            self.frames = [URL(fileURLWithPath: keyframe)]
            self.currentFrameIndex = 0
        } else {
            self.frames = []
        }
        updateCurrentImage()
    }
    
    public func stepFrame(by delta: Int) {
        guard !frames.isEmpty else { return }
        let newIdx = max(0, min(frames.count - 1, currentFrameIndex + delta))
        if newIdx != currentFrameIndex {
            currentFrameIndex = newIdx
        }
    }
    
    private func updateCurrentImage() {
        guard frames.indices.contains(currentFrameIndex) else { return }
        let idx = currentFrameIndex
        
        if let cached = imageCache[idx] {
            self.currentImage = cached
            return
        }
        
        let url = frames[idx]
        Task.detached(priority: .userInitiated) {
            if let image = NSImage(contentsOf: url) {
                // Downsample slightly for scrubber UI if needed, but simple load is often enough if async
                await MainActor.run {
                    self.imageCache[idx] = image
                    if self.currentFrameIndex == idx {
                        self.currentImage = image
                    }
                }
            }
        }
    }

    public func playTimelapseVideo(for card: TimelineCard) {
        // If pre-generated video exists on disk, play it immediately
        if let existing = card.timelapseVideoPath, FileManager.default.fileExists(atPath: existing) {
            let url = URL(fileURLWithPath: existing)
            let p = AVPlayer(url: url)
            self.player = p
            self.showVideoModal = true
            p.play()
            return
        }

        // Ensure we have frames (or fallback to keyframe)
        if frames.isEmpty {
            loadFrames(for: card)
        }
        guard !frames.isEmpty else { return }

        isGeneratingVideo = true
        Task {
            let tempDir = FileManager.default.temporaryDirectory
            let outURL = tempDir.appendingPathComponent("timelapse_\(card.id.uuidString).mp4")

            do {
                let videoURL = try await TimelapseGenerator.shared.generateTimelapseVideo(frameURLs: frames, outputURL: outURL)
                // Cache generated video path
                var updated = card
                updated.timelapseVideoPath = videoURL.path
                DatabaseManager.shared.saveCard(updated)

                let p = AVPlayer(url: videoURL)
                self.player = p
                self.showVideoModal = true
                p.play()
            } catch {
                print("[TimelapseScrubberView] Video compilation error: \(error)")
            }
            self.isGeneratingVideo = false
        }
    }

    public func closeVideoModal() {
        self.player?.pause()
        self.player = nil
        self.showVideoModal = false
    }
}

public struct TimelapseScrubberView: View {
    let card: TimelineCard
    @ObservedObject var vm: ScrubberViewModel

    public init(card: TimelineCard, vm: ScrubberViewModel = ScrubberViewModel()) {
        self.card = card
        self.vm = vm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                // Background Frame Display with Direct Hover Scrubber
                GeometryReader { geo in
                    ZStack {
                        if let nsImage = vm.currentImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: 160)
                                .clipped()
                        } else if let keyframe = card.keyframePath, let nsImage = NSImage(contentsOfFile: keyframe) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: 160)
                                .clipped()
                        } else {
                            placeholderView
                                .frame(width: geo.size.width, height: 160)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            vm.isHovering = true
                            guard !vm.frames.isEmpty, geo.size.width > 0 else { return }
                            let fraction = max(0.0, min(1.0, location.x / geo.size.width))
                            let targetIndex = Int(fraction * Double(vm.frames.count - 1))
                            if targetIndex != vm.currentFrameIndex {
                                vm.currentFrameIndex = targetIndex
                            }
                        case .ended:
                            vm.isHovering = false
                        }
                    }
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    // Subtle dark gradient vignette at the bottom for controls readability
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
                )

                // Controls Overlay
                HStack(alignment: .center) {
                    // Frame counter
                    if vm.frames.count > 1 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 5, height: 5)
                            Text("\(vm.currentFrameIndex + 1) / \(vm.frames.count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // Play Video Button
                    if vm.isGeneratingVideo {
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 14, height: 14)
                            Text("Сборка...")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    } else {
                        Button {
                            vm.playTimelapseVideo(for: card)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("Таймлапс")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color.accentColor, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }

            // Sleek Glowing Scrubber Bar
            if vm.frames.count > 1 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 3)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.7), Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(Double(vm.currentFrameIndex + 1) / Double(vm.frames.count))), height: 3)
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 4, x: 0, y: 0)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 2)
            }
        }
        .task {
            vm.loadFrames(for: card)
        }
        .sheet(isPresented: $vm.showVideoModal) {
            if let player = vm.player {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            Text("Таймлапс сессии (\(card.durationFormatted))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            vm.closeVideoModal()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay(Divider(), alignment: .bottom)

                    NativePlayerView(player: player)
                        .frame(width: 760, height: 480)
                }
                .frame(width: 760, height: 536)
                .background(Color.black)
            }
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.04))
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Кадры в процессе записи")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            )
    }
}
