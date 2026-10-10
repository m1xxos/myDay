import Foundation
import SwiftUI
import AVFoundation

public struct DaySummaryView: View {
    @ObservedObject var appState: AppState
    @StateObject private var vm = DaySummaryViewModel()
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Итоги дня")
                        .font(.system(size: 20, weight: .bold))
                    
                    Text(appState.selectedDate, style: .date)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    appState.isShowingDaySummary = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            HStack(spacing: 0) {
                // Video Player
                ZStack {
                    Color.black
                    if let player = vm.videoPlayer {
                        NativePlayerView(player: player)
                    } else if vm.isGenerating {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Сборка таймлапса дня...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Нет кадров за этот день.")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 500)
                
                Divider()
                
                // AI Summary
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if vm.isGenerating && vm.aiSummary == "Анализирую день..." {
                            ProgressView()
                                .padding(.bottom, 8)
                        }
                        
                        Text(vm.aiSummary)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                    }
                    .padding(24)
                }
                .frame(width: 360)
            }
        }
        .frame(width: 860, height: 500)
        .onAppear {
            vm.generateSummary(for: appState.selectedDate, cards: appState.cards, appState: appState)
        }
    }
}
