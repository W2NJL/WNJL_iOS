import Foundation
import CarPlay
import Combine
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupObservers()
        updateCarPlayTemplate()
    }

    private func setupObservers() {
        let radioPlayer = RadioPlayer.shared

        radioPlayer.$nowPlaying
            .sink { [weak self] _ in
                self?.updateCarPlayTemplate()
            }
            .store(in: &cancellables)

        radioPlayer.$albumArt
            .sink { [weak self] _ in
                self?.updateCarPlayTemplate()
            }
            .store(in: &cancellables)

        radioPlayer.$isPlaying
            .sink { [weak self] _ in
                self?.updateCarPlayTemplate()
            }
            .store(in: &cancellables)
    }

    private func updateCarPlayTemplate() {
        let radioPlayer = RadioPlayer.shared

        fetchAlbumArtImage(for: radioPlayer.albumArt) { albumArtImage in
            // Create album art or app icon grid item
            let albumArtGridItem = CPGridButton(
                titleVariants: [radioPlayer.nowPlaying],
                image: albumArtImage ?? UIImage(named: "CarPlayIcon")!
            ) { _ in
                print("Album Art or App Icon Tapped")
            }

            // Create play/pause grid button
            let playPauseGridButton = CPGridButton(
                titleVariants: [radioPlayer.isPlaying ? "Pause" : "Play"],
                image: UIImage(systemName: radioPlayer.isPlaying ? "pause.circle" : "play.circle")!
            ) { _ in
                RadioPlayer.shared.togglePlayPause()
                self.updateCarPlayTemplate() // Update the template immediately
            }

            // Create the grid template
            let gridTemplate = CPGridTemplate(
                title: "WNJL.com Radio",
                gridButtons: [albumArtGridItem, playPauseGridButton]
            )

            // Set the template on the CarPlay interface
            DispatchQueue.main.async {
                self.interfaceController?.setRootTemplate(gridTemplate, animated: true)
            }
        }
    }

    private func fetchAlbumArtImage(for albumArtURL: URL?, completion: @escaping (UIImage?) -> Void) {
        guard let albumArtURL = albumArtURL else {
            // Use the fallback album art if no URL is provided
            fetchFallbackAlbumArt(completion: completion)
            return
        }

        URLSession.shared.dataTask(with: albumArtURL) { data, _, error in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                // If the fetch fails, use the fallback album art
                self.fetchFallbackAlbumArt(completion: completion)
            }
        }.resume()
    }

    private func fetchFallbackAlbumArt(completion: @escaping (UIImage?) -> Void) {
        guard let fallbackURL = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png") else {
            DispatchQueue.main.async {
                completion(UIImage(systemName: "music.note"))
            }
            return
        }

        URLSession.shared.dataTask(with: fallbackURL) { data, _, error in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                DispatchQueue.main.async {
                    completion(UIImage(systemName: "music.note"))
                }
            }
        }.resume()
    }
}
