import SwiftUI
import Photos

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var photoManager = PhotoManager()
    @State private var selectedMode: PhotoMode? = nil
    @State private var showingReview = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if !photoManager.hasResolvedInitialAuthorization {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading")
                } else if photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited {
                    modeSelectionView
                } else if photoManager.authorizationStatus == .notDetermined {
                    requestPermissionView
                } else {
                    deniedPermissionView
                }
            }
            .navigationTitle("Photo Cleaner")
            .toolbar {
                if !photoManager.deletionQueue.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingReview = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.red)
                        }
                        .badge(photoManager.deletionQueue.count)
                    }
                }
            }
            .fullScreenCover(item: $selectedMode) { mode in
                SwipeView(
                    photoManager: photoManager,
                    onRequestReview: {
                        selectedMode = nil
                        DispatchQueue.main.async {
                            showingReview = true
                        }
                    },
                    onOpenReviewQueue: {
                        showingReview = true
                    }
                )
                // Sheet must be on the presented cover; a sheet on the root stays under fullScreenCover.
                .sheet(isPresented: $showingReview) {
                    ReviewQueueView(photoManager: photoManager)
                }
                .onAppear {
                    photoManager.fetchPhotos(mode: mode)
                }
            }
            .task {
                await photoManager.performInitialAuthorizationRead()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    photoManager.refreshAuthorizationFromSystem()
                }
            }
        }
    }
    
    private var modeSelectionView: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("Ready to clean?")
                        .font(.title2.bold())
                    
                    Text("Select a mode to start swiping through your photos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }
            
            Section {
                ForEach(PhotoMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: modeIcon(for: mode))
                                .font(.title3)
                                .frame(width: 28, alignment: .center)
                                .foregroundStyle(.tint)
                            Text(mode.rawValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Choose a cleaning mode")
            }
            
            if !photoManager.deletionQueue.isEmpty {
                Section {
                    Button(action: {
                        showingReview = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .frame(width: 30)
                                .foregroundColor(.red)
                            Text("Review Deletion Queue")
                                .foregroundColor(.red)
                            Spacer()
                            Text("\(photoManager.deletionQueue.count)")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .font(.caption.bold())
                        }
                    }
                }
            }
        }
        .sheet(isPresented: homeReviewSheetBinding) {
            ReviewQueueView(photoManager: photoManager)
        }
    }
    
    /// Only present from the home list when swipe isn’t covering the screen (avoids two sheets on one flag).
    private var homeReviewSheetBinding: Binding<Bool> {
        Binding(
            get: { showingReview && selectedMode == nil },
            set: { showingReview = $0 }
        )
    }
    
    private func modeIcon(for mode: PhotoMode) -> String {
        switch mode {
        case .newest: return "arrow.down.circle.fill"
        case .oldest: return "arrow.up.circle.fill"
        case .screenshots: return "iphone"
        case .random: return "shuffle"
        }
    }
    
    private var requestPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Access Required")
                .font(.title)
                .bold()
            
            Text("To help you clean your photo library, we need permission to read and delete photos.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Grant Access") {
                Task {
                    await photoManager.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var deniedPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            
            Text("Access Denied")
                .font(.title)
                .bold()
            
            Text("Please enable photo access in Settings to use this app.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
