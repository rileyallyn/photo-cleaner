import SwiftUI
import Photos

struct CardView: View {
    let asset: PHAsset
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    
    @State private var offset: CGSize = .zero
    @State private var image: UIImage? = nil
    
    private let threshold: CGFloat = 150
    
    var body: some View {
        ZStack {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            
            // Badges pinned to corners — avoid HStack/VStack + Spacer() which inflates unbounded height in ZStack parents.
            ZStack(alignment: .topLeading) {
                Color.clear
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("KEEP")
                }
                .font(.title.bold())
                .padding()
                .background(Color.green.opacity(0.8))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .rotationEffect(.degrees(-15))
                .opacity(Double(offset.width / threshold))
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            ZStack(alignment: .topTrailing) {
                Color.clear
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("DELETE")
                }
                .font(.title.bold())
                .padding()
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .rotationEffect(.degrees(15))
                .opacity(Double(-offset.width / threshold))
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .offset(x: offset.width, y: offset.height * 0.4)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                }
                .onEnded { gesture in
                    if offset.width > threshold {
                        // Swipe Right - KEEP
                        withAnimation {
                            offset = CGSize(width: 1000, height: 0)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSwipeRight()
                        }
                    } else if offset.width < -threshold {
                        // Swipe Left - DELETE
                        withAnimation {
                            offset = CGSize(width: -1000, height: 0)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSwipeLeft()
                        }
                    } else {
                        // Reset
                        withAnimation(.spring()) {
                            offset = .zero
                        }
                    }
                }
        )
        .onAppear {
            loadImage()
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            offset = .zero
            image = nil
            loadImage()
        }
    }
    
    private func loadImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 1000, height: 1000),
                             contentMode: .aspectFill,
                             options: options) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}
