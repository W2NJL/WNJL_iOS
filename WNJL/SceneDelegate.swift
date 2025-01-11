import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let contentView = ContentView()

        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }

        // Check if the app is launched in CarPlay mode and set autoplay accordingly
        if isInCarPlay(scene) {
            RadioPlayer.shared.shouldAutoplay = true
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        print("Scene became active")
        
        if isInCarPlay(scene) {
            print("Activated in CarPlay")
            // Automatically start playback in CarPlay
            if !RadioPlayer.shared.isPlaying {
                RadioPlayer.shared.togglePlayPause()
            }
        } else {
            print("Activated on iPhone or non-CarPlay device")
            refreshAppState()
        }
    }

    private func refreshAppState() {
        print("Refreshing app state...")
        RadioPlayer.shared.fetchNowPlaying()
        RadioPlayer.shared.fetchLastPlayed()
    }

    private func isInCarPlay(_ scene: UIScene) -> Bool {
        if let windowScene = scene as? UIWindowScene {
            return UIScreen.screens.contains { $0.traitCollection.userInterfaceIdiom == .carPlay }
        }
        return false
    }
}
