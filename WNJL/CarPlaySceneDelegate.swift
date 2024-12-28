import Foundation
import CarPlay
import AVFoundation

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var audioPlayer: AVPlayer?
    private var currentSong: String = "Loading..."
    private var isPlaying: Bool = false
    private var songUpdateTimer: Timer?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupAudioPlayer()
        setListTemplate()
        startSongUpdates()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        stopSongUpdates()
    }

    private func setupAudioPlayer() {
        guard let url = URL(string: "https://d4cbg8stml4t6.cloudfront.net/stream") else {
            print("Invalid stream URL")
            return
        }
        audioPlayer = AVPlayer(url: url)
    }

    private func setListTemplate() {
        // Play/Pause Button
        let playPauseItem = CPListItem(
            text: "Play/Pause",
            detailText: isPlaying ? "Playing" : "Paused"
        )
        playPauseItem.handler = { [weak self] _, _ in
            self?.togglePlayPause()
        }

        // Current Song Display
        let nowPlayingItem = CPListItem(
            text: "Now Playing",
            detailText: currentSong
        )

        let section = CPListSection(items: [playPauseItem, nowPlayingItem])
        let listTemplate = CPListTemplate(title: "WNJL Radio", sections: [section])

        interfaceController?.setRootTemplate(listTemplate, animated: true)
    }

    private func updateListTemplate() {
        guard let interfaceController = interfaceController else { return }

        let playPauseItem = CPListItem(
            text: "Play/Pause",
            detailText: isPlaying ? "Playing" : "Paused"
        )
        playPauseItem.handler = { [weak self] _, _ in
            self?.togglePlayPause()
        }

        let nowPlayingItem = CPListItem(
            text: "Now Playing",
            detailText: currentSong
        )

        let section = CPListSection(items: [playPauseItem, nowPlayingItem])
        let listTemplate = CPListTemplate(title: "WNJL Radio", sections: [section])

        interfaceController.setRootTemplate(listTemplate, animated: true)
    }

    private func togglePlayPause() {
        guard let player = audioPlayer else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }

        isPlaying.toggle()
        updateListTemplate()
    }

    private func startSongUpdates() {
        songUpdateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.fetchCurrentSong()
        }
    }

    private func stopSongUpdates() {
        songUpdateTimer?.invalidate()
        songUpdateTimer = nil
    }

    private func fetchCurrentSong() {
        guard let url = URL(string: "https://m1nt0kils7.execute-api.us-east-2.amazonaws.com/prod/currentsong") else {
            print("Invalid song API URL")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, error == nil, let data = data,
                  let song = String(data: data, encoding: .utf8) else {
                print("Failed to fetch current song")
                return
            }

            DispatchQueue.main.async {
                if song != self.currentSong {
                    self.currentSong = song
                    self.updateListTemplate()
                }
            }
        }
        task.resume()
    }
}
