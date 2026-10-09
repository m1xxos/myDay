import Foundation
import SwiftUI
import AVKit

@MainActor
public final class ScrubberViewModel: ObservableObject {
    @Published public var frames: [URL] = []
    @Published public var currentFrameIndex: Int = 0
    @Published public var isHovering: Bool = false
    @Published public var isGeneratingVideo: Bool = false
    @Published public var videoPlayerURL: URL? = nil
    @Published public var showVideoModal: Bool = false

    public init() {}

    public func loadFrames(for card: TimelineCard) {
        let loaded = TimelapseStorage.shared.getFrames(between: card.startTime, and: card.endTime)
        self.frames = loaded
        if !loaded.isEmpty {
            self.currentFrameIndex = loaded.count / 2
        }
    }

    public func playTimelapseVideo(for card: TimelineCard) {
        if let existing = card.timelapseVideoPath, FileManager.default.fileExists(atPath: existing) {
            self.videoPlayerURL = URL(fileURLWithPath: existing)
            self.showVideoModal = true
            return
        }

        guard !frames.isEmpty else { return }

        isGeneratingVideo = true
        Task {
            let tempDir = FileManager.default.temporaryDirectory
            let outURL = tempDir.appendingPathComponent("timelapse_\(card.id.uuidString).mp4")

            do {
                let videoURL = try await TimelapseGenerator.shared.generateTimelapseVideo(frameURLs: frames, outputURL: outURL)
                self.videoPlayerURL = videoURL
                self.showVideoModal = true
            } catch {
                print("[TimelapseScrubberView] Video compilation error: \(error)")
            }
            self.isGeneratingVideo = false
        }
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
                // Background Frame Display
                ZStack {
                    if !vm.frames.isEmpty && vm.currentFrameIndex < vm.frames.count {
                        if let nsImage = NSImage(contentsOf: vm.frames[vm.currentFrameIndex]) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 160)
                                .clipped()
                        } else {
                            placeholderView
                        }
                    } else if let keyframe = card.keyframePath, let nsImage = NSImage(contentsOfFile: keyframe) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .clipped()
                    } else {
                        placeholderView
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    // Subtle dark gradient vignette at the bottom for controls readability
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
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
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
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
            .contentShape(Rectangle())
            // Mouse hover scrubber
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    vm.isHovering = true
                    guard !vm.frames.isEmpty else { return }
                    let fraction = max(0.0, min(1.0, location.x / 300.0))
                    let targetIndex = Int(fraction * Double(vm.frames.count - 1))
                    if targetIndex != vm.currentFrameIndex {
                        vm.currentFrameIndex = targetIndex
                    }
                case .ended:
                    vm.isHovering = false
                }
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
                                    colors: [Color.accentColor.opacity(0.7), Color.accentColor],
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
            if let videoURL = vm.videoPlayerURL {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(.headline)
                            Text("Ускоренный таймлапс сессии")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Закрыть") {
                            vm.showVideoModal = false
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding(16)
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay(Divider(), alignment: .bottom)

                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .frame(width: 720, height: 450)
                }
                .frame(width: 720, height: 506)
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
