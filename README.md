# Photo Cleaner

A modern, fast, and intuitive iOS application designed to help you declutter your photo library. Swipe through your photos, screenshots, and more to quickly decide what to keep and what to delete.

![App Icon](photo-cleaner/AppIcon.icon/Assets/image_search_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24%202.svg)

## Features

- **Multiple Cleaning Modes**:
  - **Newest First**: Start with your most recent memories.
  - **Oldest First**: Go back in time and clean up old clutter.
  - **Screenshots**: Specifically target screenshots that are often temporary.
  - **Random**: Shake things up with a random selection of photos.
- **Intuitive Swiping Interface**: Swiftly decide on photos with a simple left (delete) or right (keep) swipe.
- **Deletion Queue**: Review your marked photos before final deletion to prevent accidental loss.
- **Persistent Queue**: Your deletion queue is saved across app launches.
- **Privacy Focused**: Operates entirely on-device using Apple's PhotoKit. No data ever leaves your device.

## Getting Started

### Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ device or simulator
- Apple Developer Account (for on-device testing)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/photo-cleaner.git
   ```
2. Open `photo-cleaner.xcodeproj` in Xcode.
3. Select your target device or simulator.
4. Build and Run (`Cmd + R`).

## Architecture

The app is built using **SwiftUI** and follows a modern MVVM-like pattern with a centralized `PhotoManager` handling the interaction with `PhotoKit`.

- **ContentView**: The main entry point and mode selection screen.
- **SwipeView**: The core interactive swiping experience.
- **CardView**: Individual photo cards with gesture handling.
- **ReviewQueueView**: Final review before permanent deletion.
- **PhotoManager**: Observable object managing photo fetching, authorization, and the deletion queue.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Acknowledgements

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Powered by [PhotoKit](https://developer.apple.com/documentation/photokit)
