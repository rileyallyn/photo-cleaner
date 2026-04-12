import SwiftUI
import Photos

struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage? = nil
    @Environment(\.displayScale) private var displayScale
    
    private let pointSize: CGFloat = 100
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: pointSize, height: pointSize)
                    .clipped()
            } else {
                Color.gray.opacity(0.12)
                    .frame(width: pointSize, height: pointSize)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            requestThumbnail()
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            image = nil
            requestThumbnail()
        }
    }
    
    /// `targetSize` is in **pixels**; `100` alone is far too small on Retina and often yields PHPhotosError 3303.
    private func requestThumbnail() {
        let scale = max(displayScale, 2)
        let px = CGSize(width: pointSize * scale, height: pointSize * scale)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.version = .current
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: px,
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            DispatchQueue.main.async {
                if let result {
                    self.image = result
                } else if let error = info?[PHImageErrorKey] as? Error {
                    #if DEBUG
                    print("Thumbnail request failed: \(error)")
                    #endif
                }
            }
        }
    }
}

struct ReviewQueueView: View {
    @ObservedObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var errorMessage: String? = nil
    @State private var previewItem: QueuedPhotoPreviewItem?
    
    var body: some View {
        NavigationStack {
            Group {
                if photoManager.deletionQueue.isEmpty {
                    emptyQueueContent
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(Array(photoManager.deletionQueue), id: \.localIdentifier) { asset in
                                ZStack(alignment: .topTrailing) {
                                    AssetThumbnail(asset: asset)
                                    
                                    Button {
                                        photoManager.removeFromDeletionQueue(asset)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red, .white)
                                            .symbolRenderingMode(.palette)
                                    }
                                    .padding(4)
                                }
                                .contentShape(Rectangle())
                                .onLongPressGesture(minimumDuration: 0.45) {
                                    previewItem = QueuedPhotoPreviewItem(asset: asset)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Review deletions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !photoManager.deletionQueue.isEmpty {
                    Button {
                        showingAlert = true
                    } label: {
                        Text("Delete \(photoManager.deletionQueue.count) photos")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .alert("Confirm deletion", isPresented: $showingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await photoManager.deleteQueuedPhotos()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("These photos will be removed from your library. This cannot be undone.")
        }
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .fullScreenCover(item: $previewItem) { item in
            DeletionQueuePhotoPreview(asset: item.asset)
        }
    }
    
    private var emptyQueueContent: some View {
        ContentUnavailableView {
            Label("Nothing queued", systemImage: "trash")
        } description: {
            Text("Photos you swipe to delete will appear here before you remove them from your library.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Long-press full-screen preview

private struct QueuedPhotoPreviewItem: Identifiable {
    let id: String
    let asset: PHAsset
    
    init(asset: PHAsset) {
        self.asset = asset
        self.id = asset.localIdentifier
    }
}

private struct DeletionQueuePhotoPreview: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var imageRequestID: PHImageRequestID = PHInvalidImageRequestID
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .tint(.white)
                }
            }
        }
        .onAppear {
            loadPreviewImage()
        }
        .onDisappear {
            if imageRequestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(imageRequestID)
                imageRequestID = PHInvalidImageRequestID
            }
        }
    }
    
    private func loadPreviewImage() {
        image = nil
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        
        let w = max(CGFloat(asset.pixelWidth), 1)
        let h = max(CGFloat(asset.pixelHeight), 1)
        let maxEdge: CGFloat = 4096
        let scale = min(maxEdge / max(w, h), 1)
        let target = CGSize(width: w * scale, height: h * scale)
        
        imageRequestID = manager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            DispatchQueue.main.async {
                if let result {
                    self.image = result
                }
                self.imageRequestID = PHInvalidImageRequestID
            }
        }
    }
}
