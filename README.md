# Scrollery

A UIKit gallery that loads images from [Picsum Photos](https://picsum.photos/) as you scroll.

## Run

Requires Xcode 26.5 or newer and an iOS 26.5 or newer simulator/device. There are no third-party dependencies.

Open `infinite-gallery.xcodeproj`, select the shared `infinite-gallery` scheme, choose an iPhone or iPad simulator, and run. A physical device requires your own signing team. Image loading requires an internet connection.

## Test

Run Product > Test in Xcode, or choose an available simulator ID from `xcrun simctl list devices available`:

```sh
xcodebuild -project infinite-gallery.xcodeproj -scheme infinite-gallery \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

The XCTest target covers HTTP/decode errors, cache size keys, original image bytes, disk eviction, cancellation/deduplication, Retina sizing and rotation, circuit breaker recovery, and retry backoff. Network responses and disk directories are isolated in tests; Picsum availability is not required. Tests run serially because the app has shared network/circuit breaker state.

GitHub Actions runs the same suite on pushes and pull requests using Xcode 26.5 on the [macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md). Test result bundles are retained for seven days.

## Image loading

- Request dimensions are pixels, calculated from the cell's size in points and its screen scale. Memory, disk, and in-flight request keys include image ID, pixel width, and pixel height. Rotation cancels obsolete requests and reloads the appropriate size.
- Memory caching uses `NSCache` with a 50 MiB cost limit. iOS can evict entries earlier under memory pressure.
- Disk caching stores the original downloaded bytes without recompression, with a 100 MiB limit. Oldest stored files are evicted first, including legacy cache files. Images larger than the limit are displayed without being written to disk. Legacy ID-only JPEG entries are not reused for sized requests.
- Disk entries become stale after one hour. Stale images are displayed while a background request refreshes them.
- Up to four network operations run concurrently. Transient failures retry up to four times with exponential backoff, 20% jitter, and an eight-second delay cap. Cancellation finishes operations and settles waiting callbacks once.
- The circuit breaker opens after five consecutive server/connectivity failures. It permits a recovery probe after 15 seconds, increases the open interval on failed probes up to 60 seconds, and closes after success.
- Image IDs and loading states are persisted locally. On launch, states reset to idle so the appropriate cached or downloaded size can be loaded.
