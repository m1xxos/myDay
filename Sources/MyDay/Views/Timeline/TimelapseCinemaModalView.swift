import Foundation
import SwiftUI
import AppKit
import AVFoundation

public struct TimelapseCinemaModalView: View {
    let card: TimelineCard
    @ObservedObject var appState: AppState
    @ObservedObject var vm: ScrubberViewModel
    @Environment(\.dismiss) private var dismiss

    public init(card: TimelineCard, appState: AppState) {
        self.card = card
        self.appState = appState
        self.vm = appState.scrubberVM(for: card)
    }

    private var timeRangeString: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let start = df.string(from: card.startTime)
        let end = df.string(from: card.endTime)
        return "\(start) – \(end) · \(card.durationFormatted)"
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Cinema Top Bar
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)

                    Text(timeRangeString + " · \(max(1, vm.frames.count)) кадров")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Export / Video Play Button
                if vm.isGeneratingVideo {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                        Text("Сборка MP4...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                } else if vm.player == nil {
                    Button {
                        vm.playTimelapseVideo(for: card)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "film")
                                .font(.system(size: 10))
                            Text("MP4 Видео")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Собрать непрерывное 30fps MP4 видео через видеочип Apple Silicon")
                }

                // Close Button
                Button {
                    vm.stopPlayback()
                    if vm.player != nil {
                        vm.closeVideoModal()
                    }
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.85))

            Divider()
                .overlay(Color.white.opacity(0.12))

            // MARK: - Main Cinema Screen Stage
            ZStack {
                Color.black.ignoresSafeArea()

                if let player = vm.player {
                    NativePlayerView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let nsImage = vm.currentImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let kf = card.keyframePath, let nsImage = NSImage(contentsOfFile: kf) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Нет сохраненных скриншотов")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .overlay(Color.white.opacity(0.12))

            // MARK: - Bottom Scrubber & Transport Controls
            VStack(spacing: 10) {
                // Time & Frame Badge + Keyboard hint
                HStack {
                    if !vm.frames.isEmpty {
                        Text("Кадр \(vm.currentFrameIndex + 1) из \(vm.frames.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text("Пробел: Старт/Пауза  ·  Стрелки ← / →: Покадрово")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // High-precision Interactive Scrubber Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 6)

                        // Progress
                        let total = max(1, vm.frames.count)
                        let progress = CGFloat(vm.currentFrameIndex + 1) / CGFloat(total)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, geo.size.width * progress), height: 6)

                        // Draggable thumb
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                            .offset(x: max(0, min(geo.size.width - 14, (geo.size.width * progress) - 7)))
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !vm.frames.isEmpty, geo.size.width > 0 else { return }
                                let fraction = max(0.0, min(1.0, value.location.x / geo.size.width))
                                let target = Int(fraction * Double(vm.frames.count - 1))
                                if target != vm.currentFrameIndex {
                                    vm.currentFrameIndex = target
                                }
                            }
                    )
                }
                .frame(height: 24)
                .padding(.horizontal, 20)

                // Playback Transport Buttons
                HStack(spacing: 16) {
                    // Previous Frame
                    Button {
                        vm.stepFrame(by: -1)
                    } label: {
                        Image(systemName: "backward.frame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    // Play / Pause Slideshow
                    Button {
                        vm.togglePlayback()
                    } label: {
                        Image(systemName: vm.isPlayingSlideshow ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])

                    // Next Frame
                    Button {
                        vm.stepFrame(by: 1)
                    } label: {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.rightArrow, modifiers: [])

                    // Speed Selector Button
                    Button {
                        vm.cycleSpeed()
                    } label: {
                        Text("\(Int(vm.playbackSpeed))x")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Скорость показа слайдов")
                }
                .padding(.bottom, 14)
            }
            .background(Color.black.opacity(0.92))
        }
        .frame(minWidth: 880, idealWidth: 1000, maxWidth: 1200, minHeight: 580, idealHeight: 680, maxHeight: 850)
        .background(Color.black)
        .task {
            vm.loadFrames(for: card)
            vm.currentFrameIndex = 0
        }
        .onDisappear {
            vm.stopPlayback()
        }
    }
}
