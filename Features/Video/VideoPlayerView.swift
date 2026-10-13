import SwiftUI
import AVKit
import AVFoundation
import Combine

struct VideoPlayerView: View {
    let videoURL: URL?
    let book: Book?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerState = VideoPlayerState()
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var showSpeedPicker = false
    @State private var showQualityPicker = false
    @State private var showPlaylist = false
    @State private var isLandscape = false
    @State private var playbackSpeed: Float = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = playerState.player {
                videoPlayerLayer(player)
            } else {
                loadingOrErrorView
            }

            if showControls {
                controlsOverlay
            }
        }
        .statusBarHidden(true)
        .onAppear {
            setupPlayer()
            startControlsTimer()
        }
        .onDisappear {
            playerState.player?.pause()
            controlsTimer?.invalidate()
        }
        .onRotate { orientation in
            isLandscape = orientation.isLandscape
        }
        .sheet(isPresented: $showSpeedPicker) {
            speedPickerSheet
        }
        .sheet(isPresented: $showPlaylist) {
            playlistSheet
        }
    }

    private func videoPlayerLayer(_ player: AVPlayer) -> some View {
        AVPlayerViewControllerRepresentable(player: player, playerState: playerState)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls.toggle()
                }
                if showControls { startControlsTimer() }
            }
    }

    private var loadingOrErrorView: some View {
        VStack(spacing: 16) {
            if playerState.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("加载中...")
                    .foregroundColor(.white)
            } else {
                Image(systemName: "video.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                Text(playerState.errorMessage ?? "无法加载视频")
                    .foregroundColor(.gray)
                Button("重试") {
                    setupPlayer()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack {
            Button(action: { playerState.player?.pause(); dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            Spacer()

            if let title = book?.name {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { showPlaylist = true }) {
                Image(systemName: "list.bullet")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let player = playerState.player {
                playerProgressView(player)
            }

            HStack(spacing: 24) {
                Button(action: { playerState.seekBackward(15) }) {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .foregroundColor(.white)
                }

                Button(action: { playerState.togglePlay() }) {
                    Image(systemName: playerState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }

                Button(action: { playerState.seekForward(15) }) {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .foregroundColor(.white)
                }

                Spacer()

                Button(action: { showSpeedPicker = true }) {
                    Text(speedLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }

                Button(action: { togglePictureInPicture() }) {
                    Image(systemName: "pip.enter")
                        .font(.title3)
                        .foregroundColor(.white)
                }

                Button(action: { toggleFullscreen() }) {
                    Image(systemName: isLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        )
    }

    private func playerProgressView(_ player: AVPlayer) -> some View {
        VideoProgressView(playerState: playerState)
            .frame(height: 20)
            .padding(.horizontal, 16)
    }

    private var speedLabel: String {
        playbackSpeed == 1.0 ? "1x" : "\(String(format: playbackSpeed < 1 ? "%.1f" : "%.0f", playbackSpeed))x"
    }

    private var speedPickerSheet: some View {
        NavigationView {
            List {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { speed in
                    Button(action: {
                        playbackSpeed = Float(speed)
                        playerState.setSpeed(Float(speed))
                        showSpeedPicker = false
                    }) {
                        HStack {
                            Text("\(String(format: speed < 1 ? "%.2f" : "%.0f", speed))x")
                            Spacer()
                            if abs(Float(speed) - playbackSpeed) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("播放速度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showSpeedPicker = false }
                }
            }
        }
    }

    private var playlistSheet: some View {
        NavigationView {
            List {
                if let chapters = book?.chapters?.allObjects as? [BookChapter] {
                    ForEach(chapters.sorted(by: { $0.index < $1.index }), id: \.index) { chapter in
                        Button(action: {
                            loadChapter(chapter)
                            showPlaylist = false
                        }) {
                            HStack {
                                Text(chapter.title ?? "第\(chapter.index + 1)章")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if chapter.index == playerState.currentChapterIndex {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showPlaylist = false }
                }
            }
        }
    }

    private func setupPlayer() {
        guard let url = videoURL else {
            playerState.errorMessage = "无效的视频地址"
            return
        }
        playerState.load(url: url)
    }

    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }

    private func togglePictureInPicture() {
        if AVPictureInPictureController.isPictureInPictureSupported() {
            playerState.togglePiP()
        }
    }

    private func toggleFullscreen() {
        if isLandscape {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }
    }

    private func loadChapter(_ chapter: BookChapter) {
        guard !chapter.chapterUrl.isEmpty, let url = URL(string: chapter.chapterUrl) else { return }
        playerState.load(url: url)
        playerState.currentChapterIndex = Int(chapter.index)
    }
}

struct VideoProgressView: UIViewRepresentable {
    @ObservedObject var playerState: VideoPlayerState

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.tintColor = .systemBlue
        slider.addTarget(context.coordinator, action: #selector(Coordinator.onSliderChanged), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.onSliderReleased), for: .touchUpInside)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.onSliderReleased), for: .touchUpOutside)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        if !playerState.isSeeking {
            slider.value = Float(playerState.progress)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(playerState: playerState)
    }

    class Coordinator {
        let playerState: VideoPlayerState

        init(playerState: VideoPlayerState) {
            self.playerState = playerState
        }

        @objc func onSliderChanged(_ slider: UISlider) {
            Task { @MainActor in
                playerState.isSeeking = true
            }
        }

        @objc func onSliderReleased(_ slider: UISlider) {
            Task { @MainActor in
                playerState.seekToProgress(Double(slider.value))
                playerState.isSeeking = false
            }
        }
    }
}

@MainActor
class VideoPlayerState: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var errorMessage: String?
    @Published var isSeeking = false
    @Published var currentChapterIndex: Int = 0

    private var timeObserver: Any?
    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?

    func load(url: URL) {
        isLoading = true
        errorMessage = nil

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer

        setupPlayerLayer(newPlayer)
        setupTimeObserver(newPlayer)
        setupNotifications(item)

        newPlayer.play()
        isPlaying = true
        isLoading = false
    }

    func togglePlay() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seekBackward(_ seconds: Double) {
        guard let player = player else { return }
        let target = player.currentTime() - CMTime(seconds: seconds, preferredTimescale: 1)
        player.seek(to: max(target, .zero))
    }

    func seekForward(_ seconds: Double) {
        guard let player = player else { return }
        let target = player.currentTime() + CMTime(seconds: seconds, preferredTimescale: 1)
        player.seek(to: target)
    }

    func seekToProgress(_ progress: Double) {
        guard let player = player, duration > 0 else { return }
        let targetTime = CMTime(seconds: progress * duration, preferredTimescale: 1)
        player.seek(to: targetTime)
    }

    func setSpeed(_ speed: Float) {
        player?.rate = speed
    }

    func startPictureInPicture() {
        pipController?.startPictureInPicture()
    }

    func togglePiP() {
        if let pip = pipController {
            if pip.isPictureInPictureActive {
                pip.stopPictureInPicture()
            } else {
                pip.startPictureInPicture()
            }
        }
    }

    private func setupPlayerLayer(_ player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        if let layer = playerLayer, AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: layer)
            pipController?.delegate = nil
        }
    }

    private func setupTimeObserver(_ player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
          Task { @MainActor in
            guard let self = self else { return }
            self.currentTime = time.seconds.isFinite ? max(0, time.seconds) : 0
            if self.duration > 0 {
                self.progress = self.currentTime / self.duration
            }
          }
        }
    }

    private func setupNotifications(_ item: AVPlayerItem) {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }

        item.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.duration = item.duration.seconds
                    self?.isLoading = false
                case .failed:
                    self?.errorMessage = item.error?.localizedDescription ?? "播放失败"
                    self?.isLoading = false
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    deinit {
        Task { @MainActor in
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
        }
    }
}

struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    @ObservedObject var playerState: VideoPlayerState

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(playerState: playerState)
    }

    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let playerState: VideoPlayerState
        weak var controller: AVPlayerViewController?

        init(playerState: VideoPlayerState) {
            self.playerState = playerState
        }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
            return false
        }

        func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
    }
}

extension View {
    func onRotate(_ action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            action(UIDevice.current.orientation)
        }
    }
}
