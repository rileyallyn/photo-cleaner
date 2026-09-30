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
final class PhotoManager: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var deletionQueue: Set<PHAsset> = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var deletionQueueSize: Int64 = 0
    /// `false` until the first `PHPhotoLibrary.authorizationStatus` read finishes — avoids blocking first frame.
    @Published var hasResolvedInitialAuthorization = false
    @Published var isLoading = false
    /// Mode for the current swipe session (set when `fetchPhotos` completes).
    @Published var activeMode: PhotoMode? = nil
    /// Total photos loaded for the current session (for progress UI).
    @Published var sessionTotalCount: Int = 0
    
    private static let deletionQueueStorageKey = "PhotoManager.deletionQueue.localIdentifiers"
    
    /// Bumps whenever a new total-size calculation starts; stale background work ignores the result.
    private var deletionQueueSizeCalculationID = 0
    
    private let libraryChangeObserver = PhotoLibraryChangeObserver()
    
    init() {
        libraryChangeObserver.photoManager = self
    }
    
    /// Call from `ContentView.task` so the window can render before touching PhotoKit.
    func performInitialAuthorizationRead() async {
        guard !hasResolvedInitialAuthorization else { return }
        await Task.yield()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasResolvedInitialAuthorization = true
        loadPersistedDeletionQueueIfAllowed()
    }
    
    /// Refresh status after returning from Settings or other apps (`scenePhase == .active`).
    func refreshAuthorizationFromSystem() {
        let previous = authorizationStatus
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorizationStatus != previous {
            loadPersistedDeletionQueueIfAllowed()
        }
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
        
        let queuedIds = Set(deletionQueue.map(\.localIdentifier))
        Task {
            let fetched = await Self.fetchAssetsInBackground(mode: mode, excludingLocalIdentifiers: queuedIds)
            self.assets = fetched
            self.sessionTotalCount = fetched.count
            self.activeMode = mode
            self.isLoading = false
        }
    }
    
    func addToDeletionQueue(_ asset: PHAsset) {
        deletionQueue.insert(asset)
        persistDeletionQueueIdentifiers()
        calculateDeletionQueueSize()
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
        deletionQueueSizeCalculationID += 1
        deletionQueueSize = 0
        persistDeletionQueueIdentifiers()
    }
    
    func removeFromDeletionQueue(_ asset: PHAsset) {
        deletionQueue.remove(asset)
        persistDeletionQueueIdentifiers()
        calculateDeletionQueueSize()
    }
    
    func calculateDeletionQueueSize() {
        deletionQueueSizeCalculationID += 1
        let calculationID = deletionQueueSizeCalculationID
        let snapshot = Array(deletionQueue)
        
        Task.detached {
            var total: Int64 = 0
            for asset in snapshot {
                let bytes = await Self.byteLengthForPrimaryResource(of: asset)
                total += bytes
                let obsolete = await MainActor.run { [weak self] in
                    guard let self else { return true }
                    return calculationID != self.deletionQueueSizeCalculationID
                }
                if obsolete { return }
            }
            let finalTotal = total
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard calculationID == self.deletionQueueSizeCalculationID else { return }
                self.deletionQueueSize = finalTotal
            }
        }
    }
    
    /// Sum of `Data` chunks delivered for the asset’s first resource via `PHAssetResourceManager`
    nonisolated private static func byteLengthForPrimaryResource(of asset: PHAsset) async -> Int64 {
        await withCheckedContinuation { continuation in
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first else {
                continuation.resume(returning: 0)
                return
            }
            var total: Int64 = 0
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: nil,
                dataReceivedHandler: { data in
                    total += Int64(data.count)
                },
                completionHandler: { _ in
                    continuation.resume(returning: total)
                }
            )
        }
    }
    
    nonisolated private static func fetchAssetsInBackground(
        mode: PhotoMode,
        excludingLocalIdentifiers: Set<String>
    ) async -> [PHAsset] {
        await Task.detached {
            let fetchOptions = PHFetchOptions()
            switch mode {
            case .newest:
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            case .oldest:
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            case .screenshots:
                fetchOptions.predicate = NSPredicate(
                    format: "(mediaSubtype & %d) != 0",
                    PHAssetMediaSubtype.photoScreenshot.rawValue
                )
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            case .random:
                break
            }
            
            let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var fetchedAssets: [PHAsset] = []
            allPhotos.enumerateObjects { asset, _, _ in
                fetchedAssets.append(asset)
            }
            var filtered = fetchedAssets.filter { !excludingLocalIdentifiers.contains($0.localIdentifier) }
            if mode == .random {
                filtered.shuffle()
            }
            return filtered
        }.value
    }
    
    fileprivate func handlePhotoLibraryChange(_: PHChange) {
        guard hasResolvedInitialAuthorization else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        
        if !assets.isEmpty {
            let ids = assets.map(\.localIdentifier)
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var existing = Set<String>()
            fetch.enumerateObjects { asset, _, _ in
                existing.insert(asset.localIdentifier)
            }
            let filtered = assets.filter { existing.contains($0.localIdentifier) }
            if filtered.count != assets.count {
                assets = filtered
            }
        }
        
        if !deletionQueue.isEmpty {
            let ids = deletionQueue.map(\.localIdentifier)
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var newQueue = Set<PHAsset>()
            fetch.enumerateObjects { asset, _, _ in
                newQueue.insert(asset)
            }
            if newQueue.count != deletionQueue.count {
                deletionQueue = newQueue
                persistDeletionQueueIdentifiers()
                calculateDeletionQueueSize()
            }
        }
    }
    
    
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
        calculateDeletionQueueSize()
        if restored.count != stored.count {
            persistDeletionQueueIdentifiers()
        }
    }
}

/// Lives at file scope so it is not `@MainActor`-isolated
private final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    weak var photoManager: PhotoManager?
    
    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak photoManager] in
            photoManager?.handlePhotoLibraryChange(changeInstance)
        }
    }
}
