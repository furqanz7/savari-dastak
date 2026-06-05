import SwiftUI
import AVKit

struct SplashView: View {
    @State private var currentLoopIndex: Int = Int.random(in: 0..<3) // random starting video
    @State private var animateText = false
    
    let loops = ["sawari1", "sawari2", "sawari3", "sawari4", "sawari5"]
    
    var body: some View {
        ZStack {
            LoopingVideoPlayer(videoNames: loops, currentIndex: $currentLoopIndex)
                .ignoresSafeArea()
                .onAppear {
                    startLoopSequence()
                }
            
            HStack(spacing: 16) {
                Text("Savari")
                    .font(.system(size: 48, weight: .thin, design: .default))
                    .foregroundColor(.primary)
                    .shadow(color: .white.opacity(0.2), radius: 10)
                
                Text("ساواری")
                    .font(.custom("JameelNooriNastaleeq", size: 48))
                    .fontWeight(.light)
                    .foregroundColor(.primary)
                    .shadow(color: .white.opacity(0.2), radius: 10)
            }
            .scaleEffect(animateText ? 1.0 : 0.9)
            .opacity(animateText ? 1.0 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) {
                    animateText = true
                }
            }
        }
    }
    
    private func startLoopSequence() {
        let loopDuration: TimeInterval = 5
        Timer.scheduledTimer(withTimeInterval: loopDuration, repeats: true) { _ in
            currentLoopIndex = (currentLoopIndex + 1) % loops.count
        }
    }
}

// MARK: Reactive Looping Video Player
struct LoopingVideoPlayer: UIViewRepresentable {
    let videoNames: [String]
    @Binding var currentIndex: Int
    
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(playerLayer)
        
        playVideo(at: currentIndex)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Only replace item if the index changed
        if let currentItem = player.currentItem,
           let url = (currentItem.asset as? AVURLAsset)?.url,
           let expectedPath = Bundle.main.path(forResource: videoNames[currentIndex], ofType: "mp4"),
           url.path != expectedPath {
            playVideo(at: currentIndex)
        }
    }
    
    private func playVideo(at index: Int) {
        guard index < videoNames.count,
              let path = Bundle.main.path(forResource: videoNames[index], ofType: "mp4") else { return }
        
        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: path))
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = true
        player.play()
    }
}

#Preview {
    SplashView()
}
