import CoreLocation
import MapKit
import SwiftUI
import Photos

struct CardView: View {
    let asset: PHAsset
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    @State private var offset: CGSize = .zero
    @State private var image: UIImage? = nil
    @State private var imageRequestID: PHImageRequestID = PHInvalidImageRequestID
    @State private var isShowingDetails = false
    @State private var zoomScale: CGFloat = 1.0
    
    private let threshold: CGFloat = 150
    private let dragMinimumDistance: CGFloat = 28
    
    var body: some View {
        ZStack {
            flipStack
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
        .gesture(swipeDragGesture)
        .simultaneousGesture(flipTapGesture)
        // Pinch must not use an exclusive `.gesture` on the image — that blocks the card’s drag.
        .simultaneousGesture(photoMagnificationGesture)
        .onAppear {
            loadImage()
        }
        .onDisappear {
            cancelImageRequest()
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            cancelImageRequest()
            offset = .zero
            image = nil
            zoomScale = 1.0
            isShowingDetails = false
            loadImage()
        }
    }
    
    private var flipStack: some View {
        ZStack {
            photoFace
                .rotation3DEffect(
                    .degrees(isShowingDetails ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: 0.92
                )
                // Without z-index, the opaque metadata face draws above the photo even when “rotated away” —
                // SwiftUI doesn’t cull back-faces, so the image disappears.
                .zIndex(isShowingDetails ? 0 : 1)
                .allowsHitTesting(!isShowingDetails)
            PhotoMetadataBackView(asset: asset)
                .rotation3DEffect(
                    .degrees(isShowingDetails ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: 0.92
                )
                .zIndex(isShowingDetails ? 1 : 0)
                .allowsHitTesting(isShowingDetails)
        }
    }
    
    private var photoFace: some View {
        ZStack {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(zoomScale)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            
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
    }
    
    private var swipeDragGesture: some Gesture {
        DragGesture(minimumDistance: dragMinimumDistance)
            .onChanged { gesture in
                offset = gesture.translation
            }
            .onEnded { _ in
                // Gesture transactions disable implicit animation; defer so `withAnimation` applies.
                DispatchQueue.main.async {
                    endSwipeDrag()
                }
            }
    }
    
    private var photoMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !isShowingDetails else { return }
                zoomScale = max(1.0, min(4.0, value))
            }
            .onEnded { _ in
                guard !isShowingDetails else { return }
                if accessibilityReduceMotion {
                    zoomScale = 1.0
                } else {
                    withAnimation(.spring()) {
                        zoomScale = 1.0
                    }
                }
            }
    }
    
    private var flipTapGesture: some Gesture {
        TapGesture()
            .onEnded {
                if accessibilityReduceMotion {
                    isShowingDetails.toggle()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        isShowingDetails.toggle()
                    }
                }
            }
    }
    
    private static let swipeFlyOutDuration: TimeInterval = 0.32
    
    private func endSwipeDrag() {
        let reduceMotion = accessibilityReduceMotion
        if offset.width > threshold {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if reduceMotion {
                offset = CGSize(width: 1000, height: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onSwipeRight()
                }
            } else {
                withAnimation(.easeInOut(duration: Self.swipeFlyOutDuration)) {
                    offset = CGSize(width: 1000, height: 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.swipeFlyOutDuration) {
                    onSwipeRight()
                }
            }
        } else if offset.width < -threshold {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if reduceMotion {
                offset = CGSize(width: -1000, height: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onSwipeLeft()
                }
            } else {
                withAnimation(.easeInOut(duration: Self.swipeFlyOutDuration)) {
                    offset = CGSize(width: -1000, height: 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.swipeFlyOutDuration) {
                    onSwipeLeft()
                }
            }
        } else {
            if reduceMotion {
                offset = .zero
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    offset = .zero
                }
            }
        }
    }
    
    private func cancelImageRequest() {
        if imageRequestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(imageRequestID)
            imageRequestID = PHInvalidImageRequestID
        }
    }
    
    private func loadImage() {
        cancelImageRequest()
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        let assetId = asset.localIdentifier
        imageRequestID = manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 1000, height: 1000),
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            DispatchQueue.main.async {
                guard assetId == self.asset.localIdentifier else { return }
                if let result {
                    self.image = result
                }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded {
                    self.imageRequestID = PHInvalidImageRequestID
                }
            }
        }
    }
}

// MARK: - Metadata back

private struct PhotoMetadataBackView: View {
    let asset: PHAsset
    
    @State private var placeLabel: String?
    @State private var geocodeFailed = false
    @State private var activeReverseRequest: MKReverseGeocodingRequest?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Photo info")
                    .font(.title2.weight(.bold))
                
                if let date = asset.creationDate {
                    metadataRow(icon: "calendar", title: "Date", value: date.formatted(date: .long, time: .omitted))
                    metadataRow(icon: "clock", title: "Time", value: date.formatted(date: .omitted, time: .shortened))
                } else {
                    metadataRow(icon: "calendar", title: "Date", value: "Unknown")
                }
                
                metadataRow(
                    icon: "aspectratio",
                    title: "Dimensions",
                    value: "\(asset.pixelWidth) × \(asset.pixelHeight)"
                )
                
                if let loc = asset.location {
                    if let placeLabel {
                        metadataRow(icon: "mappin.and.ellipse", title: "Location", value: placeLabel)
                    } else if geocodeFailed {
                        metadataRow(
                            icon: "location",
                            title: "Coordinates",
                            value: String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude)
                        )
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            ProgressView()
                                .controlSize(.small)
                            Text("Looking up location…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    metadataRow(icon: "location.slash", title: "Location", value: "None in photo")
                }
                
                if asset.isFavorite {
                    Label("Favorite", systemImage: "heart.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.pink)
                }
                
                if asset.mediaSubtypes.contains(.photoScreenshot) {
                    Label("Screenshot", systemImage: "iphone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text("Tap to flip back")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            resolvePlaceIfNeeded()
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            activeReverseRequest?.cancel()
            activeReverseRequest = nil
            placeLabel = nil
            geocodeFailed = false
            resolvePlaceIfNeeded()
        }
    }
    
    private func metadataRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }
    
    private func resolvePlaceIfNeeded() {
        guard let location = asset.location else { return }
        placeLabel = nil
        geocodeFailed = false
        
        activeReverseRequest?.cancel()
        activeReverseRequest = nil
        
        guard let request = MKReverseGeocodingRequest(location: location) else {
            geocodeFailed = true
            return
        }
        activeReverseRequest = request
        let assetId = asset.localIdentifier
        
        Task { @MainActor in
            do {
                let items = try await request.mapItems
                guard assetId == asset.localIdentifier else { return }
                activeReverseRequest = nil
                if let item = items.first {
                    placeLabel = formattedPlace(from: item)
                } else {
                    geocodeFailed = true
                }
            } catch {
                guard assetId == asset.localIdentifier else { return }
                activeReverseRequest = nil
                geocodeFailed = true
            }
        }
    }
    
    private func formattedPlace(from item: MKMapItem) -> String {
        let coordinate = item.location.coordinate
        let coords = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        if let name = item.name, !name.isEmpty {
            if let full = item.address?.fullAddress, !full.isEmpty {
                return "\(name) · \(full)"
            }
            return name
        }
        if let full = item.address?.fullAddress, !full.isEmpty {
            return full
        }
        return coords
    }
}
