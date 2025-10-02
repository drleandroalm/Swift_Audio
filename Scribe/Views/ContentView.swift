import Speech
import SwiftData
import SwiftUI
import os

// MARK: - Notification Names
extension Notification.Name {
    static let recordingStateChanged = Notification.Name("SSRecordingStateChanged")
}

struct ContentView: View {
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @State var selection: Memo?
    @State private var showingSettings = false
    @State private var isRecording = false  // Track recording state globally
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            ZStack {
                List(selection: $selection) {
                    ForEach(memos) { memo in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(memo.title))
                                .font(.headline)
                            Text(memo.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !memo.text.characters.isEmpty {
                                Text(
                                    String(memo.text.characters.prefix(50))
                                        + (memo.text.characters.count > 50 ? "..." : "")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }
                        }
                        .tag(memo)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .onDelete(perform: deleteMemos)
                }
                .navigationTitle("Memorandos")
                .navigationSplitViewColumnWidth(min: 250, ideal: 250, max: 400)
                .toolbar {
                    #if os(iOS)
                        // Keep only settings and edit buttons in toolbar
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            if !memos.isEmpty {
                                EditButton()
                            }

                            Button {
                                showingSettings = true
                            } label: {
                                Label("Configurações", systemImage: "gearshape")
                            }
                        }
                    #elseif os(macOS)
                        // On macOS, settings are in the app menu, so only show the Add button
                        ToolbarItemGroup(placement: .primaryAction) {
                            if !memos.isEmpty && selection != nil {
                                Button {
                                    if let selection = selection {
                                        deleteMemo(selection)
                                    }
                                } label: {
                                    Label("Excluir Memorando", systemImage: "trash")
                                }
                                .foregroundColor(.red)
                            }

                            if !isRecording {
                                Button {
                                    addMemo()
                                } label: {
                                    Label("Novo Memorando", systemImage: "plus")
                                }
                            }
                        }
                    #endif
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .toolbarBackground(.hidden)

                #if os(iOS)
                    // Floating New button at the bottom for iOS
                    if !isRecording {
                        VStack {
                            Spacer()

                            Button {
                                addMemo()
                            } label: {
                                Label("Novo", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.extraLarge)
                            .tint(Color(red: 0.36, green: 0.69, blue: 0.55))  // Using the app's green color
                            .padding(.bottom, 24)
                        }
                    }
                #endif
            }
        } detail: {
            if let memo = selection {
                TranscriptView(memo: memo, isRecording: $isRecording)
                    .background(
                        LinearGradient(colors: [Color.black.opacity(0.02), Color.gray.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                    )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(Color(red: 0.36, green: 0.69, blue: 0.55))
                    Text("Selecione um item")
                        .font(.title3).foregroundStyle(.secondary)
                    Button {
                        addMemo()
                    } label: {
                        Label("Novo Memorando", systemImage: "plus.circle.fill")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.glass)
                    .tint(Color(red: 0.36, green: 0.69, blue: 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings)
            }
        #endif
        .onAppear {
            let timestamp = Date().timeIntervalSince1970
            Log.ui.info("ContentView: onAppear chamado at timestamp=\(timestamp, privacy: .public)")
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            let autoRecVal = env["SS_AUTO_RECORD"] ?? "nil"
            Log.ui.info("ContentView: SS_AUTO_RECORD = \(autoRecVal, privacy: .public)")
            if env["SS_AUTO_RECORD"] == "1" || CommandLine.arguments.contains("--headless-record") {
                let hasSelection = selection != nil
                Log.ui.info("ContentView: Auto-record ativado! selection=\(hasSelection ? "presente" : "nil", privacy: .public) isRecording=\(isRecording ? "true" : "false", privacy: .public)")
                if selection == nil {
                    addMemo()
                    Log.ui.info("ContentView: Novo memo criado, selection agora definida")
                }
                // Use Task instead of DispatchQueue for better control
                // Longer delay (800ms) to ensure UI is fully settled before triggering recording
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    let currentTimestamp = Date().timeIntervalSince1970
                    Log.ui.info("ContentView: Auto-record delay completo at timestamp=\(currentTimestamp, privacy: .public)")
                    guard !isRecording else {
                        Log.ui.warning("ContentView: isRecording já é true, pulando auto-start duplicado")
                        return
                    }
                    Log.ui.info("ContentView: Definindo isRecording=true (auto-record) oldValue=false newValue=true")
                    isRecording = true
                }
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SSTriggerRecordFromURL"))) { _ in
            guard settings.allowURLRecordTrigger else { return }
            if selection == nil { addMemo() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isRecording = true }
        }
        .onChange(of: isRecording) { oldValue, newValue in
            let timestamp = Date().timeIntervalSince1970
            // Only post notification if values actually differ
            guard oldValue != newValue else {
                Log.state.info("ContentView: isRecording unchanged at timestamp=\(timestamp, privacy: .public) (\(newValue ? "true" : "false", privacy: .public)), skipping notification")
                return
            }
            Log.state.info("ContentView: isRecording changed at timestamp=\(timestamp, privacy: .public) from \(oldValue ? "true" : "false", privacy: .public) to \(newValue ? "true" : "false", privacy: .public)")

            // Add small delay to ensure UI cycle completes before posting notification
            // This prevents race conditions where rapid state changes confuse SwiftUI
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                let postTimestamp = Date().timeIntervalSince1970
                Log.state.info("ContentView: Posting recordingStateChanged notification at timestamp=\(postTimestamp, privacy: .public)")
                NotificationCenter.default.post(
                    name: .recordingStateChanged,
                    object: nil,
                    userInfo: ["oldValue": oldValue, "newValue": newValue]
                )
                Log.state.info("ContentView: Notification posted successfully")
            }
        }
    }

    private func addMemo() {
        let newMemo = Memo.blank()
        modelContext.insert(newMemo)
        selection = newMemo
    }

    private func deleteMemos(offsets: IndexSet) {
        for index in offsets {
            deleteMemo(memos[index])
        }
    }

    private func deleteMemo(_ memo: Memo) {
        if selection == memo {
            selection = nil
        }
        modelContext.delete(memo)
    }
}
