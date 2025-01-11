import SwiftUI
import AVFoundation
import MediaPlayer
import Foundation

// Data model for songs
struct Song: Identifiable {
    let id = UUID()
    let time: String
    let artist: String
    let title: String
    var albumArt: URL? = nil
}

// ObservableObject for shared state
class RadioPlayer: NSObject, ObservableObject {
    static let shared = RadioPlayer()
    @Published var nowPlaying: String = "Loading..."
    @Published var lastPlayed: [Song] = []
    @Published var albumArt: URL? = nil
    @Published var isPlaying: Bool = false
    var shouldAutoplay: Bool = false // Default to not autoplaying

    private var albumArtCache: [String: URL] = [:] // Cache for album art
    
    private var audioPlayer: AVPlayer?
    private var fetchTimer: Timer?
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let playerItem = object as? AVPlayerItem {
            if playerItem.status == .failed {
                print("Playback failed. Reinitializing player.")
                reinitializePlayer()
            }
        }
        
        if keyPath == "playbackLikelyToKeepUp", let playerItem = object as? AVPlayerItem {
               if playerItem.isPlaybackLikelyToKeepUp {
                   print("Buffering complete. Resuming playback if paused.")
                   if let player = audioPlayer, player.rate == 0 {
                       player.play()
                       isPlaying = true
                   }
               } else {
                   print("Buffering...")
               }
           }
    }
    
    
    
    private func reinitializePlayer() {
        audioPlayer?.pause()
        audioPlayer = nil
        setupAudioPlayer()
        audioPlayer?.play()
        isPlaying = true
    }
    
    func convertToLocalTime(gmtTime: String) -> String? {
        // Define the expected format of the input time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss" // Shoutcast time format
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // GMT timezone
        
        // Parse the GMT time string into a Date object
        guard let date = dateFormatter.date(from: gmtTime) else {
            return nil // Return nil if parsing fails
        }
        
        // Set the formatter to the device's local timezone
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "h:mm a" // Adjust to desired output format, e.g., "12:34 PM"
        
        // Return the local time string
        return dateFormatter.string(from: date)
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("Audio session configured for background playback.")
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    override init() {
        super.init() // Call the superclass initializer
        setupAudioPlayer()
        setupRemoteCommands()
        configureAudioSession()
        startFetching()
    }
    
    deinit {
        stopFetching()
        
        // Remove observer to avoid potential crashes
            audioPlayer?.currentItem?.removeObserver(self, forKeyPath: "status")
        audioPlayer?.currentItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
    }
    
    @objc private func handlePlaybackStalled() {
        print("Playback stalled, attempting to resume...")
        
        // Attempt to resume playback
        if let player = audioPlayer, player.rate == 0 {
            player.play()
        }
    }
    

    
    private func setupAudioPlayer() {
        if audioPlayer == nil {
            guard let url = URL(string: "https://d4cbg8stml4t6.cloudfront.net/stream") else {
                print("Invalid stream URL")
                return
            }
            audioPlayer = AVPlayer(url: url)

            // Add observer for buffering status and playback stalled
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePlaybackStalled),
                name: .AVPlayerItemPlaybackStalled,
                object: audioPlayer?.currentItem
            )
            
            audioPlayer?.currentItem?.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)

            // Only start playback automatically if shouldAutoplay is true
            if shouldAutoplay {
                print("Auto-playing due to CarPlay mode")
                audioPlayer?.play()
                isPlaying = true
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = audioPlayer else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { _ in
            RadioPlayer.shared.togglePlayPause()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { _ in
            RadioPlayer.shared.togglePlayPause()
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying,
            MPMediaItemPropertyArtist: "WNJL.com Radio"
        ]

        // Check cache for album art
        if let cachedAlbumArtURL = albumArtCache[nowPlaying],
           let imageData = try? Data(contentsOf: cachedAlbumArtURL),
           let image = UIImage(data: imageData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        } else if let defaultImage = UIImage(named: "WNJLLogo") {
            // Use default image if no album art is available
            let artwork = MPMediaItemArtwork(boundsSize: defaultImage.size) { _ in defaultImage }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingInfoWithAlbumArt(
        nowPlayingInfo: inout [String: Any],
        albumArtURL: URL?
    ) {
        guard let albumArtURL = albumArtURL,
              let imageData = try? Data(contentsOf: albumArtURL),
              let image = UIImage(data: imageData) else {
            // Use default image if album art fails to load
            if let defaultImage = UIImage(named: "WNJLLogo") { // Ensure "WNJLLogo" exists in Assets
                let artwork = MPMediaItemArtwork(boundsSize: defaultImage.size) { _ in defaultImage }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
            return
        }

        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }
    
    private func startFetching() {
        fetchNowPlaying()
        updateNowPlayingInfo()
        fetchLastPlayed()
        fetchTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.fetchNowPlaying()
            self?.fetchLastPlayed()
            self?.updateNowPlayingInfo()
        }
        
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            DispatchQueue.main.async {
                self.isPlaying = player.rate != 0
            }
        }
    }
    
    private func stopFetching() {
        fetchTimer?.invalidate()
        fetchTimer = nil
    }
    
    func fetchNowPlaying() {
        guard let url = URL(string: "https://m1nt0kils7.execute-api.us-east-2.amazonaws.com/prod/currentsong") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            // Handle network or server error
            if let error = error {
                print("Error fetching now playing: \(error.localizedDescription)")
                return
            }

            // Parse the response data
            guard let data = data, let rawText = String(data: data, encoding: .utf8) else {
                print("Failed to decode response")
                return
            }

            // Update nowPlaying and fetch album art
            let newSong = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if self.nowPlaying != newSong {
                    self.nowPlaying = newSong
                    self.fetchAlbumArt(for: newSong) { [weak self] albumArtURL in
                        guard let self = self else { return }
                        if let albumArtURL = albumArtURL {
                            self.albumArt = albumArtURL
                        }
                    }
                }
            }
        }.resume()
    }
    
    func fetchAlbumArt(for song: String, completion: @escaping (URL?) -> Void) {
        // Check the cache first
        if let cachedURL = albumArtCache[song] {
            completion(cachedURL)
            return
        }

        // Parse artist and title
        let components = song.split(separator: " - ", maxSplits: 1).map(String.init)
        guard components.count == 2, let artist = components.first, let title = components.last else {
            completion(URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png"))
            return
        }

        let urlString = "https://m1nt0kils7.execute-api.us-east-2.amazonaws.com/prod/LastFmApi?artist=\(artist)&track=\(title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        guard let url = URL(string: urlString) else {
            completion(URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png"))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let error = error {
                print("Error fetching album art: \(error.localizedDescription)")
                completion(URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png"))
                return
            }

            guard let data = data else {
                completion(URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png"))
                return
            }

            do {
                let response = try JSONDecoder().decode(AlbumArtResponse.self, from: data)
                if let largeImage = response.track?.album?.image?.first(where: { $0.size == "large" })?.text {
                    let albumArtURL = URL(string: largeImage)
                    self?.albumArtCache[song] = albumArtURL // Cache the result
                    completion(albumArtURL)
                } else {
                    completion(URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png"))
                }
            } catch {
                print("Error decoding album art response: \(error)")
                completion(URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png"))
            }
        }.resume()
    }
    
    struct AlbumArtResponse: Decodable {
        struct Track: Decodable {
            struct Album: Decodable {
                struct Image: Decodable {
                    let text: String
                    let size: String
                    
                    private enum CodingKeys: String, CodingKey {
                        case text = "#text"
                        case size
                    }
                }
                let image: [Image]?
            }
            let album: Album?
        }
        let track: Track?
    }
    
    func fetchLastPlayed() {
        guard let url = URL(string: "https://m1nt0kils7.execute-api.us-east-2.amazonaws.com/prod/last20played") else {
            print("Invalid URL for last 20 played songs")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let error = error {
                print("Error fetching last played: \(error.localizedDescription)")
                return
            }
            
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                print("Failed to decode response as HTML string")
                return
            }
            
            DispatchQueue.main.async {
                var parsedSongs = self?.parseLastPlayed(html: html) ?? []
                let dispatchGroup = DispatchGroup()
                
                for index in 0..<parsedSongs.count {
                    let song = parsedSongs[index]
                    dispatchGroup.enter()
                    
                    self?.fetchAlbumArt(for: "\(song.artist) - \(song.title)") { albumArtURL in
                        parsedSongs[index].albumArt = albumArtURL
                        dispatchGroup.leave()
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    self?.lastPlayed = parsedSongs
                    print("Updated lastPlayed with album art.")
                }
            }
        }.resume()
    }
    
    
    
    private func parseLastPlayed(html: String) -> [Song] {
        var songs: [Song] = []
        
        // Extract rows from the table by splitting on "<tr>"
        let rows = html.components(separatedBy: "</tr>")
        
        for row in rows {
            // Check if the row contains valid <td> elements
            let columns = row.components(separatedBy: "<td>")
            
            // Ensure we have at least 2 columns (time and song title)
            guard columns.count > 2 else { continue }
            
            // Extract and clean the time
            var rawTime = columns[1]
                .replacingOccurrences(of: "</td>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract and clean the song title
            var rawTitle = columns[2]
                .replacingOccurrences(of: "</td>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip if the row is marked as "Current Song"
            if row.contains("Current Song") {
                continue
            }
            
            // Decode HTML entities in time and title
            rawTime = decodeHTMLEntities(rawTime)
            rawTitle = decodeHTMLEntities(rawTitle)
            
            // Convert the time to the local timezone
            let localTime = convertToLocalTime(gmtTime: rawTime) ?? rawTime // Use GMT time as fallback
            
            // Split the song title into artist and title
            let parts = rawTitle.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { continue }
            
            // Create a Song object
            let song = Song(time: localTime, artist: parts[0], title: parts[1])
            songs.append(song)
        }
        
        return songs
    }}

private func decodeHTMLEntities(_ text: String) -> String {
    let entities: [String: String] = [
        "&apos;": "'",
        "&quot;": "\"",
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">"
    ]
    
    var decodedText = text
    for (entity, character) in entities {
        decodedText = decodedText.replacingOccurrences(of: entity, with: character)
    }
    return decodedText
}

// ContentView
import SwiftUI


struct ContentView: View {
    @ObservedObject private var radioPlayer = RadioPlayer.shared
    @Environment(\.scenePhase) private var scenePhase // Detect scene phase changes

    var body: some View {
        VStack(spacing: 20) {
            // WNJL Header
            HStack {
                Image("WNJLLogo") // Ensure "WNJLLogo" is in Assets.xcassets
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                Text("WNJL.com Radio")
                    .font(.headline)
            }
            .padding(.bottom, 10) // Add some spacing below the header
            // Album Art
            AsyncImage(url: radioPlayer.albumArt ?? URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .cornerRadius(10)
            } placeholder: {
                Image("WNJLLogo") // Use the WNJLLogo from Assets.xcassets
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .cornerRadius(10)
            }

            // Now Playing
            Text("Now Playing")
                .font(.headline)
            Text(radioPlayer.nowPlaying)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            // Play/Pause Button
            Button(action: {
                radioPlayer.togglePlayPause()
            }) {
                Image(systemName: radioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
            }

            Divider()

            // Last 10 Played Songs
            Text("Last 10 Played Songs")
                .font(.headline)

            List(radioPlayer.lastPlayed) { song in
                HStack {
                    AsyncImage(url: song.albumArt ?? URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .cornerRadius(5)
                    } placeholder: {
                        Image("WNJLLogo") // Use the WNJLLogo for fallback
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .cornerRadius(5)
                    }

                    VStack(alignment: .leading) {
                        Text("\(song.time)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("\(song.artist) - \(song.title)")
                            .font(.body)
                    }
                }
            }
        }
        .padding()
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("Scene phase changed from \(oldPhase) to \(newPhase)")
            
            if newPhase == .active {
                refreshAppState()
            }
        }
    }

    private func refreshAppState() {
        // Refresh the app's state
        print("App resumed - refreshing state")
        radioPlayer.fetchNowPlaying()
        radioPlayer.fetchLastPlayed()
    }
}
