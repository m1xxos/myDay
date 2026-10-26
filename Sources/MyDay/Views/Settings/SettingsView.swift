import Foundation
import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var engineMode: EngineMode = .native
    @Published public var endpoint: String = ""
    @Published public var selectedModel: String = ""
    @Published public var analysisMode: AnalysisMode = .textFirst
    @Published public var captureInterval: Double = 20.0
    @Published public var batchDuration: Int = 10
    @Published public var idleTimeout: Double = 120.0
    @Published public var diffThreshold: Double = 2.5
    @Published public var retentionDays: Int = 7
    @Published public var autoAnalyze: Bool = true
    @Published public var excludePrivateBrowsing: Bool = true
    @Published public var connectionStatus: String? = nil

    public init() {}

    public func load(from settings: UserSettings) {
        self.engineMode = settings.engineMode
        self.endpoint = settings.lmStudioEndpoint
        self.selectedModel = settings.selectedModel
        self.analysisMode = settings.analysisMode
        self.captureInterval = settings.captureIntervalSeconds
        self.batchDuration = settings.batchDurationMinutes
        self.idleTimeout = settings.idleTimeoutSeconds
        self.diffThreshold = settings.diffThresholdPercent
        self.retentionDays = settings.retentionDays
        self.autoAnalyze = settings.autoAnalyze
        self.excludePrivateBrowsing = settings.excludePrivateBrowsing
    }

    public func testConnection(appState: AppState) {
        connectionStatus = "Проверка..."
        Task {
            do {
                let models = try await LMStudioClient.shared.fetchAvailableModels(baseURL: endpoint)
                appState.availableModels = models
                appState.isLMStudioConnected = true
                self.connectionStatus = "OK! Найдено моделей: \(models.count)"
                if !models.contains(selectedModel), let first = models.first {
                    self.selectedModel = first
                }
            } catch {
                self.connectionStatus = "Ошибка подключения: \(error.localizedDescription)"
                appState.isLMStudioConnected = false
            }
        }
    }

    public func save(to appState: AppState) {
        var updated = appState.settings
        updated.engineMode = engineMode
        updated.lmStudioEndpoint = endpoint
        updated.selectedModel = selectedModel
        updated.analysisMode = analysisMode
        updated.captureIntervalSeconds = captureInterval
        updated.batchDurationMinutes = batchDuration
        updated.idleTimeoutSeconds = idleTimeout
        updated.diffThresholdPercent = diffThreshold
        updated.retentionDays = retentionDays
        updated.autoAnalyze = autoAnalyze
        updated.excludePrivateBrowsing = excludePrivateBrowsing

        appState.updateSettings(updated)
    }
}

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState, vm: SettingsViewModel = SettingsViewModel()) {
        self.appState = appState
        self.vm = vm
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Настройки MyDay")
                    .font(.headline)
                Spacer()
                Button("Готово") {
                    vm.save(to: appState)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .bottom)

            Form {
                // Section 1: Режим движка анализа
                Section {
                    Picker("Режим работы:", selection: $vm.engineMode) {
                        Text(EngineMode.native.displayName).tag(EngineMode.native)
                        Text(EngineMode.lmStudio.displayName).tag(EngineMode.lmStudio)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Image(systemName: vm.engineMode == .native ? "bolt.fill" : "cpu")
                            .foregroundColor(vm.engineMode == .native ? .blue : .purple)
                        Text(vm.engineMode.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)

                    if vm.engineMode == .lmStudio {
                        TextField("Endpoint LM Studio:", text: $vm.endpoint)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Проверить соединение") {
                                vm.testConnection(appState: appState)
                            }
                            if let status = vm.connectionStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundColor(status.contains("OK") ? .green : .red)
                            }
                        }

                        if !appState.availableModels.isEmpty {
                            Picker("Модель:", selection: $vm.selectedModel) {
                                ForEach(appState.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }

                        Picker("Режим анализа:", selection: $vm.analysisMode) {
                            ForEach(AnalysisMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        Text(vm.analysisMode.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Автоматический анализ при закрытии блока", isOn: $vm.autoAnalyze)
                    }
                } header: {
                    Text("Движок анализа и описания активности")
                }

                // Section 2: Оптимизация захвата
                Section {
                    HStack {
                        Text("Интервал снимков:")
                        Spacer()
                        Text("\(Int(vm.captureInterval)) сек")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $vm.captureInterval, in: 10...60, step: 5)

                    HStack {
                        Text("Длительность блока:")
                        Spacer()
                        Text("\(vm.batchDuration) мин")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(vm.batchDuration) },
                        set: { vm.batchDuration = Int($0) }
                    ), in: 5...30, step: 5)

                    HStack {
                        Text("Таймаут неактивности:")
                        Spacer()
                        Text("\(Int(vm.idleTimeout)) сек")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $vm.idleTimeout, in: 60...300, step: 30)

                    HStack {
                        Text("Порог изменения экрана:")
                        Spacer()
                        Text("\(String(format: "%.1f", vm.diffThreshold))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $vm.diffThreshold, in: 1.0...10.0, step: 0.5)
                } header: {
                    Text("Интервалы и аппаратная оптимизация")
                }

                // Section 3: Конфиденциальность
                Section {
                    Toggle("Исключать приватные окна браузеров", isOn: $vm.excludePrivateBrowsing)
                    Text("Окна в режиме Инкогнито и Частного доступа (Zen, Safari, Chrome, Arc, Brave, Firefox и др.) автоматически не записываются.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } header: {
                    Text("Конфиденциальность")
                }

                // Section 4: Хранилище
                Section {
                    Stepper("Хранить кадры: \(vm.retentionDays) дней", value: $vm.retentionDays, in: 1...30)

                    Button("Очистить устаревшие кадры сейчас") {
                        TimelapseStorage.shared.cleanOldFrames(retentionDays: vm.retentionDays)
                        appState.showToast("Устаревшие кадры удалены")
                    }
                } header: {
                    Text("Таймлапс и хранилище")
                }
            }
            .formStyle(.grouped)
            .padding(10)
        }
        .frame(width: 500, height: 560)
        .onAppear {
            vm.load(from: appState.settings)
        }
    }
}
