import SwiftUI
import AVFoundation
import MediaPlayer

// Data model for songs
struct Song: Identifiable {
    let id = UUID()
    let time: String
    let artist: String
    let title: String
}

// ObservableObject for shared state
class RadioPlayer: ObservableObject {
    @Published var nowPlaying: String = "Loading..."
    @Published var lastPlayed: [Song] = []
    @Published var albumArt: URL? = nil
    @Published var isPlaying: Bool = false
    
    private var audioPlayer: AVPlayer?
    private var fetchTimer: Timer?
    
    
    
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
    
    init() {
        setupAudioPlayer()
        setupRemoteCommands()
            configureAudioSession()
            startFetching()
    }
    
    deinit {
        stopFetching()
    }
    
    private func setupAudioPlayer() {
        guard let url = URL(string: "https://d4cbg8stml4t6.cloudfront.net/stream") else {
            print("Invalid stream URL")
            return
        }
        audioPlayer = AVPlayer(url: url)
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

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.audioPlayer?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.audioPlayer?.pause()
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying,
            MPMediaItemPropertyArtist: "WNJL.com Radio"
        ]

        if let albumArtURL = albumArt,
           let imageData = try? Data(contentsOf: albumArtURL),
           let image = UIImage(data: imageData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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
    }
    
    private func stopFetching() {
        fetchTimer?.invalidate()
        fetchTimer = nil
    }
    
    func fetchNowPlaying() {
        guard let url = URL(string: "https://m1nt0kils7.execute-api.us-east-2.amazonaws.com/prod/currentsong") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, error == nil, let data = data,
                  let song = String(data: data, encoding: .utf8) else { return }
            
            DispatchQueue.main.async {
                self.nowPlaying = song
                self.fetchAlbumArt(for: song)
            }
        }.resume()
    }
    
    func fetchAlbumArt(for song: String) {
        let components = song.split(separator: " - ", maxSplits: 1).map(String.init)
        guard components.count == 2, let artist = components.first, let title = components.last else {
            // Fallback to default image
            DispatchQueue.main.async {
                self.albumArt = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")
            }
            return
        }

        let urlString = "https://m1nt0kils7.execute-api.us-east-2.amazonaws.com/prod/LastFmApi?artist=\(artist)&track=\(title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        guard let url = URL(string: urlString) else {
            // Fallback to default image for invalid URL
            DispatchQueue.main.async {
                self.albumArt = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")
            }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                print("Error fetching album art: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.albumArt = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.albumArt = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")
                }
                return
            }

            do {
                // Decode the JSON response
                let response = try JSONDecoder().decode(AlbumArtResponse.self, from: data)

                // Extract the "large" album art
                // Extract the "large" album art
                if let largeImage = response.track?.album?.image?.first(where: { $0.size == "large" })?.text {
                               DispatchQueue.main.async {
                                   self.albumArt = URL(string: largeImage)
                               }
                           } else {
                               // Fallback to default image if no "large" image is found
                               DispatchQueue.main.async {
                                   self.albumArt = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")
                               }
                           }
                       } catch {
                           print("Error decoding album art response: \(error)")
                           DispatchQueue.main.async {
                               self.albumArt = URL(string: "https://www.wnjl.com/assets/wnjl-BioIWmS5.png")
                           }
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
            
            // Log the raw HTML response to the console
            print("Raw HTML response:\n\(html)")
            
            DispatchQueue.main.async {
                // Parse and update lastPlayed
                self?.lastPlayed = self?.parseLastPlayed(html: html) ?? []
                
                // Log the parsed songs
                print("Parsed songs: \(self?.lastPlayed ?? [])")
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
            
            // Split the song title into artist and title
            let parts = rawTitle.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { continue }
            
            // Create a Song object
            let song = Song(time: rawTime, artist: parts[0], title: parts[1])
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
struct ContentView: View {
    @StateObject private var radioPlayer = RadioPlayer()

    var body: some View {
        VStack(spacing: 20) {
            // Album Art
            if let albumArt = radioPlayer.albumArt {
                AsyncImage(url: albumArt) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .cornerRadius(10)
                } placeholder: {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .foregroundColor(.gray)
                }
            } else {
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .foregroundColor(.gray)
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
                VStack(alignment: .leading) {
                    Text("\(song.time)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("\(song.artist) - \(song.title)")
                        .font(.body)
                }
            }
        }
        .padding()
    }
}

// Album Art API Response
struct AlbumArtResponse: Decodable {
    struct Track: Decodable {
        struct Album: Decodable {
            struct Image: Decodable {
                let url: String

                private enum CodingKeys: String, CodingKey {
                    case url = "#text"
                }
            }
            let image: [Image]?
        }
        let album: Album?
    }
    let track: Track?
}

#Preview {
    ContentView()
}
