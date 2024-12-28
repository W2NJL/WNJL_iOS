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

        // Create album art grid item
        let albumArtGridItem: CPGridButton = {
            if let albumArtURL = radioPlayer.albumArt,
               let imageData = try? Data(contentsOf: albumArtURL),
               let image = UIImage(data: imageData) {
                return CPGridButton(titleVariants: ["Now Playing"], image: image) { _ in
                    print("Album Art Tapped")
                }
            } else {
                // Fallback to default album art
                let defaultURL = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")!
                let fallbackData = try? Data(contentsOf: defaultURL)
                let fallbackImage = fallbackData.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "music.note")!
                return CPGridButton(titleVariants: ["Now Playing"], image: fallbackImage)  { _ in
                    print("Album Art Tapped")
                }
            }
        }()

        // Create play/pause grid button
        let playPauseGridButton = CPGridButton(
            titleVariants: ["Play/Pause"],
            image: UIImage(systemName: radioPlayer.isPlaying ? "pause.circle" : "play.circle")!
        ) { _ in
            radioPlayer.togglePlayPause()
        }

        // Create the grid template
        let gridTemplate = CPGridTemplate(
            title: "WNJL Radio",
            gridButtons: [albumArtGridItem, playPauseGridButton]
        )

        // Set the template on the CarPlay interface
        interfaceController?.setRootTemplate(gridTemplate, animated: true)
    }

    private func fetchAlbumArtImage(for albumArtURL: URL?, completion: @escaping (UIImage?) -> Void) {
        // Check if a valid album art URL exists
        if let albumArtURL = albumArtURL {
            URLSession.shared.dataTask(with: albumArtURL) { data, _, error in
                if let data = data, let image = UIImage(data: data) {
                    completion(image)
                } else {
                    self.fetchFallbackAlbumArt(completion: completion)
                }
            }.resume()
        } else {
            fetchFallbackAlbumArt(completion: completion)
        }
    }

    private func fetchFallbackAlbumArt(completion: @escaping (UIImage?) -> Void) {
        // Fetch the fallback album art from the WNJL URL
        guard let fallbackURL = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: fallbackURL) { data, _, error in
            if let data = data, let image = UIImage(data: data) {
                completion(image)
            } else {
                completion(nil)
            }
        }.resume()
    }
}
