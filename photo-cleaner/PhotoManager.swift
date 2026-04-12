import Photos
import SwiftUI
import Combine

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
    @Published var isLoading = false
    /// Mode for the current swipe session (set when `fetchPhotos` completes).
    @Published var activeMode: PhotoMode? = nil
    /// Total photos loaded for the current session (for progress UI).
    @Published var sessionTotalCount: Int = 0
    
    init() {
        checkAuthorization()
    }
    
    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    func requestAuthorization() async {
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
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
    }
    
    func removeFromDeletionQueue(_ asset: PHAsset) {
        deletionQueue.remove(asset)
    }
}
