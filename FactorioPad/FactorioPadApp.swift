import SwiftUI
import UniformTypeIdentifiers

@main
final class FactorioPadApp: UIResponder, UIApplicationDelegate {
    override init() {
        FactorioLoader.logMessage("Creating the app delegate")
        FactorioLoader.restoreStartupLogFolder()
        super.init()
        // Discard unused transfer data from earlier development builds.
        UserDefaults.standard.removeObject(forKey: "FactorioAccountSourceBookmark")
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: "factorio-account.json"))
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = FactorioSceneDelegate.self
        return configuration
    }
}

final class FactorioSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        FactorioLoader.logMessage("Creating the app window")
        let window = UIWindow(windowScene: scene)
        window.rootViewController = FactorioRootController(rootView: FactorioLaunchView())
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class FactorioRootController: UIHostingController<FactorioLaunchView> {
    weak var gameController: FactorioViewController?

    override var prefersPointerLocked: Bool { gameController?.prefersPointerLocked ?? false }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.bottom, .right] }
}

extension Notification.Name {
    static let factorioStopped = Notification.Name("FactorioStopped")
    static let factorioControlsRequested = Notification.Name("FactorioControlsRequested")
}

struct FactorioLaunchView: View {
    private enum Stage { case gameSetup, openingGame, setup, syncing, playing, stopped }

    @State private var stage = Stage.openingGame
    @State private var importProgress = 0.0
    @State private var showsControls = false
    @State private var showsSaves = false
    @State private var showsFolderPicker = false
    @State private var selectsGameFolder = false
    @State private var status: String?
    @State private var stoppedMessage = "Factorio stopped."
    @State private var message: String?

    var body: some View {
        Group {
            if stage == .playing {
                FactorioMetalView(inputEnabled: !showsControls && !showsSaves && message == nil)
                    .accessibilityHidden(showsControls || showsSaves)
                    .ignoresSafeArea()
                    .persistentSystemOverlays(.hidden)
                    .statusBarHidden(true)
                    .defersSystemGestures(on: [.bottom, .trailing])
                    .overlay {
                        if showsControls {
                            FactorioControlsView(onClose: { showsControls = false }, onSaves: {
                                showsControls = false
                                showsSaves = true
                            }, logURL: FactorioLoader.startupLogURL())
                        }
                    }
            } else {
                VStack(spacing: 20) {
                    Text("FactorioPad").font(.largeTitle.bold())
                    if stage == .gameSetup {
                        Text("Import your FactorioData folder. You only need to do this once.")
                            .multilineTextAlignment(.center)
                        if let status { Text(status).foregroundStyle(.secondary) }
                        Button("Import game data") {
                            selectsGameFolder = true
                            showsFolderPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else if stage == .openingGame {
                        ProgressView("Importing game data…", value: importProgress)
                        Text(importProgress, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    } else if stage == .syncing {
                        ProgressView("Syncing saves…")
                    } else if stage == .stopped {
                        Text(status ?? "Factorio stopped.")
                            .multilineTextAlignment(.center)
                        if FactorioSaveSync.hasFolder {
                            Button("Retry save sync") { Task { await syncAfterPlay() } }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Choose save folder") { selectsGameFolder = false; showsFolderPicker = true }
                    } else {
                        Text("Choose a folder in iCloud Drive to share saves with Factorio on your computer.")
                            .multilineTextAlignment(.center)
                        if let status { Text(status).foregroundStyle(.secondary) }
                        Button("Choose save folder") { selectsGameFolder = false; showsFolderPicker = true }
                            .buttonStyle(.borderedProminent)
                        if FactorioSaveSync.hasFolder {
                            Button("Play") { Task { await syncBeforePlay() } }
                        } else {
                            Button("Play without sync") { stage = .playing }
                        }
                    }
                    if let log = FactorioLoader.startupLogURL() {
                        ShareLink("Share log", item: log)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.06))
                .preferredColorScheme(.dark)
            }
        }
        .task {
            await importGame(from: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .factorioControlsRequested)) { _ in
            showsControls = true
        }
        .sheet(isPresented: $showsSaves) {
            VStack(spacing: 20) {
                Text("Save sync").font(.title2.bold())
                Text("FactorioPad syncs saves when you open it, before the game starts.")
                    .multilineTextAlignment(.center)
                if let status { Text(status).font(.footnote).multilineTextAlignment(.center) }
                Button("Back to game") { showsSaves = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .presentationDetents([.medium])
        }
        .fileImporter(isPresented: $showsFolderPicker, allowedContentTypes: [.folder]) { result in
            do {
                let folder = try result.get()
                if selectsGameFolder {
                    Task { await importGame(from: folder) }
                    return
                }
                try FactorioSaveSync.saveFolder(folder)
                if stage == .setup {
                    Task { await syncBeforePlay() }
                } else if stage == .stopped {
                    Task { await syncAfterPlay() }
                }
            } catch {
                FactorioLoader.logMessage(error.localizedDescription)
                if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .factorioStopped)) { notification in
            stoppedMessage = notification.userInfo?["message"] as? String ?? "Factorio stopped."
            Task { await syncAfterPlay() }
        }
        .alert("Factorio", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func importGame(from folder: URL?) async {
        stage = .openingGame
        importProgress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                let progress: (Double) -> Void = { fraction in
                    DispatchQueue.main.async { importProgress = fraction }
                }
                if let folder {
                    try FactorioLoader.selectGameData(from: folder, progress: progress)
                } else {
                    try FactorioLoader.importSavedGameData(progress: progress)
                }
            }.value
            status = nil
            stage = .setup
            if folder != nil && FactorioSaveSync.hasFolder { await syncBeforePlay() }
        } catch {
            FactorioLoader.logMessage(error.localizedDescription)
            status = error.localizedDescription
            stage = .gameSetup
        }
    }

    private func syncBeforePlay() async {
        guard stage == .setup else { return }
        stage = .syncing
        FactorioLoader.logMessage("Syncing saves before the game")
        do {
            try await Task.detached(priority: .userInitiated) { try FactorioSaveSync.synchronize() }.value
            stage = .playing
        } catch {
            FactorioLoader.logMessage(error.localizedDescription)
            status = "Save sync failed: \(error.localizedDescription)"
            stage = .setup
        }
    }

    private func syncAfterPlay() async {
        guard stage == .playing || stage == .stopped else { return }
        stage = .syncing
        do {
            try await Task.detached(priority: .userInitiated) { try FactorioSaveSync.synchronize() }.value
            status = FactorioSaveSync.hasFolder ? "Saves synced. \(stoppedMessage)" : stoppedMessage
        } catch {
            status = "Save sync failed: \(error.localizedDescription) \(stoppedMessage)"
        }
        stage = .stopped
    }
}
