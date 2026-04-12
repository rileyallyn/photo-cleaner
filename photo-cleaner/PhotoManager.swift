import Combine
import Photos
import SwiftUI

enum PhotoMode: String, CaseIterable, Identifiable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case screenshots = "Screenshots"
    case random = "Random"
    
    var id: String { self.rawValue }
}

@MainActor
class PhotoManager: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var deletionQueue: Set<PHAsset> = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    /// `false` until the first `PHPhotoLibrary.authorizationStatus` read finishes — avoids blocking first frame.
    @Published var hasResolvedInitialAuthorization = false
    @Published var isLoading = false
    /// Mode for the current swipe session (set when `fetchPhotos` completes).
    @Published var activeMode: PhotoMode? = nil
    /// Total photos loaded for the current session (for progress UI).
    @Published var sessionTotalCount: Int = 0
    
    private static let deletionQueueStorageKey = "PhotoManager.deletionQueue.localIdentifiers"
    
    init() {}
    
    /// Call from `ContentView.task` so the window can render before touching PhotoKit.
    func performInitialAuthorizationRead() async {
        guard !hasResolvedInitialAuthorization else { return }
        await Task.yield()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasResolvedInitialAuthorization = true
        loadPersistedDeletionQueueIfAllowed()
    }
    
    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    func requestAuthorization() async {
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        loadPersistedDeletionQueueIfAllowed()
    }
    
    func fetchPhotos(mode: PhotoMode) {
        isLoading = true
        assets = []
        activeMode = nil
        sessionTotalCount = 0
        
        let fetchOptions = PHFetchOptions()
        
        switch mode {
        case .newest:
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        case .oldest:
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        case .screenshots:
            fetchOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        case .random:
            // Fetch all and then shuffle
            break
        }
        
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var fetchedAssets: [PHAsset] = []
        allPhotos.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }
        
        let queuedIds = Set(deletionQueue.map(\.localIdentifier))
        fetchedAssets = fetchedAssets.filter { !queuedIds.contains($0.localIdentifier) }
        
        if mode == .random {
            fetchedAssets.shuffle()
        }
        
        self.assets = fetchedAssets
        self.sessionTotalCount = fetchedAssets.count
        self.activeMode = mode
        self.isLoading = false
    }
    
    func addToDeletionQueue(_ asset: PHAsset) {
        deletionQueue.insert(asset)
        persistDeletionQueueIdentifiers()
        if let index = assets.firstIndex(of: asset) {
            assets.remove(at: index)
        }
    }
    
    func keepPhoto(_ asset: PHAsset) {
        if let index = assets.firstIndex(of: asset) {
            assets.remove(at: index)
        }
    }
    
    func deleteQueuedPhotos() async throws {
        let assetsToDelete = Array(deletionQueue)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }
        deletionQueue.removeAll()
        persistDeletionQueueIdentifiers()
    }
    
    func removeFromDeletionQueue(_ asset: PHAsset) {
        deletionQueue.remove(asset)
        persistDeletionQueueIdentifiers()
    }
    
    // MARK: - Deletion queue persistence
    
    private func persistDeletionQueueIdentifiers() {
        let ids = deletionQueue.map(\.localIdentifier).sorted()
        UserDefaults.standard.set(ids, forKey: Self.deletionQueueStorageKey)
    }
    
    /// Reloads queued assets from disk after the user grants access (or on cold launch when already authorized).
    private func loadPersistedDeletionQueueIfAllowed() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        guard let stored = UserDefaults.standard.stringArray(forKey: Self.deletionQueueStorageKey), !stored.isEmpty else {
            return
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: stored, options: nil)
        var restored = Set<PHAsset>()
        fetch.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image {
                restored.insert(asset)
            }
        }
        deletionQueue = restored
        if restored.count != stored.count {
            persistDeletionQueueIdentifiers()
        }
    }
}
