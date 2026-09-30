import SwiftUI
import Photos

struct SwipeView: View {
    @ObservedObject var photoManager: PhotoManager
    /// Dismiss swipe flow and present review (e.g. session finished with items queued).
    var onRequestReview: () -> Void
    /// Present review sheet without leaving swipe (toolbar).
    var onOpenReviewQueue: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var progressSubtitle: String {
        if photoManager.isLoading {
            return "Loading…"
        }
        if photoManager.sessionTotalCount == 0 {
            return "No photos to show"
        }
        if photoManager.assets.isEmpty {
            return "Session complete"
        }
        let total = photoManager.sessionTotalCount
        let remaining = photoManager.assets.count
        let current = total - remaining + 1
        return "\(current) of \(total) · \(remaining) left"
    }
    
    private var processedCount: Double {
        guard photoManager.sessionTotalCount > 0 else { return 0 }
        return Double(photoManager.sessionTotalCount - photoManager.assets.count)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if photoManager.sessionTotalCount > 0, !photoManager.isLoading {
                    ProgressView(value: processedCount, total: Double(photoManager.sessionTotalCount))
                        .tint(.accentColor)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
                
                ZStack {
                    HStack {
                        VStack {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.red.opacity(0.22))
                            Text("DELETE")
                                .font(.caption.bold())
                                .foregroundStyle(.red.opacity(0.22))
                        }
                        Spacer()
                        VStack {
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.green.opacity(0.22))
                            Text("KEEP")
                                .font(.caption.bold())
                                .foregroundStyle(.green.opacity(0.22))
                        }
                    }
                    .padding(.horizontal, 28)
                    .allowsHitTesting(false)
                    
                    if photoManager.isLoading {
                        ProgressView("Loading photos…")
                    } else if photoManager.assets.isEmpty {
                        sessionCompleteContent
                    } else {
                        // Single visible card only stacking two `CardView`s caused the back image to peek at the
                        // sides whenever the front card uses offset/rotation/shadow (layout vs. drawn bounds).
                        GeometryReader { geo in
                            let horizontalInset: CGFloat = 16
                            let verticalInset: CGFloat = 12
                            let w = max(0, geo.size.width - horizontalInset * 2)
                            let h = max(0, geo.size.height - verticalInset * 2)
                            if let asset = photoManager.assets.first {
                                CardView(asset: asset) {
                                    photoManager.addToDeletionQueue(asset)
                                } onSwipeRight: {
                                    photoManager.keepPhoto(asset)
                                }
                                .id(asset.localIdentifier)
                                .frame(width: w, height: h)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if !photoManager.isLoading, !photoManager.assets.isEmpty {
                    HStack(spacing: 40) {
                        Button {
                            if let asset = photoManager.assets.first {
                                photoManager.addToDeletionQueue(asset)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .frame(width: 56, height: 56)
                                .foregroundStyle(.red)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Delete")
                        
                        Button {
                            if let asset = photoManager.assets.first {
                                photoManager.keepPhoto(asset)
                            }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 56, height: 56)
                                .foregroundStyle(.green)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Keep")
                    }
                    .padding(.bottom, 28)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                                .fontWeight(.semibold)
                            Text("Home")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(photoManager.activeMode?.rawValue ?? "Photos")
                            .font(.headline)
                        Text(progressSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onOpenReviewQueue()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                            if photoManager.deletionQueue.count > 0 {
                                Text("\(photoManager.deletionQueue.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor))
                            }
                        }
                    }
                    .accessibilityLabel("Deletion queue")
                }
            }
        }
    }
    
    @ViewBuilder
    private var sessionCompleteContent: some View {
        VStack(spacing: 16) {
            if photoManager.sessionTotalCount == 0 {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No photos to clean")
                    .font(.title2.weight(.semibold))
                Text("Try a different mode from Home.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("You're all caught up")
                    .font(.title2.weight(.semibold))
                Text("No more photos in this session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if !photoManager.deletionQueue.isEmpty {
                Button("Review deletions") {
                    onRequestReview()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            
            Button("Back to Home") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}
