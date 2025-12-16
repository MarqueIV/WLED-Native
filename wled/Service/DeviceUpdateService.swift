import Foundation
import CoreData

/// Service responsible for identifying, downloading, and installing firmware updates for WLED devices.
@MainActor
class DeviceUpdateService {
    
    // MARK: - Properties
    
    /// List of platforms supported by the legacy update method.
    let supportedPlatforms = [
        "esp01",
        "esp02",
        "esp32",
        "esp8266",
    ]
    
    let device: DeviceWithState
    let version: Version
    let context: NSManagedObjectContext
    var githubApi: GithubApi?
    
    private var assetName: String = ""
    private(set) var couldDetermineAsset = false
    private var asset: Asset? = nil
    
    // MARK: - Initialization
    
    /// Initializes the update service and immediately attempts to determine the correct binary asset.
    ///
    /// - Parameters:
    ///   - device: The WLED device to update.
    ///   - version: The target firmware version.
    ///   - context: The Core Data context.
    init(device: DeviceWithState, version: Version, context: NSManagedObjectContext) {
        self.device = device
        self.version = version
        self.context = context
        
        // Try to use the release variable, but fallback to the legacy platform method for
        // compatibility with WLED older than 0.15.0
        if (!determineAssetByRelease()) {
            determineAssetByPlatform()
        }
    }
    
    // MARK: - API Management
    
    /// Returns the existing GitHub API instance or creates a new one if it doesn't exist.
    ///
    /// - Returns: An instance of `GithubApi`.
    func getGithubApi() -> GithubApi {
        if let githubApi = self.githubApi {
            return githubApi
        }
        let newApi = WLEDRepoApi()
        self.githubApi = newApi
        return newApi
    }
    
    // MARK: - Asset Determination Strategies
    
    /// Determines the asset to download based on the `release` variable in the device info.
    ///
    /// This is the preferred method and is typically available on WLED devices running version 0.15.0 or newer.
    ///
    /// - Returns: `true` if the asset name was determined and found; otherwise `false`.
    private func determineAssetByRelease() -> Bool {
        guard let release = device.stateInfo?.info.release,
              !release.isEmpty,
              let tagName = version.tagName else {
            return false
        }
        
        let combined = "\(tagName)_\(release)"
        let versionWithRelease = combined.lowercased().hasPrefix("v")
        ? String(combined.dropFirst())
        : combined
        
        self.assetName = "WLED_\(versionWithRelease).bin"
        return findAsset(assetName: assetName)
    }
    
    /// Determines the asset to download based on the device platform (e.g., esp32).
    ///
    /// This is a legacy method used for backwards compatibility with WLED devices older than 0.15.0.
    private func determineAssetByPlatform() {
        guard let deviceInfo = device.stateInfo?.info,
              let platformName = deviceInfo.platformName,
              let tagName = version.tagName,
              supportedPlatforms.contains(platformName) else {
            return
        }
        let combined = "\(tagName)_\(platformName.uppercased())"
        
        let versionWithPlatform = combined.lowercased().hasPrefix("v") ? String(combined.dropFirst()) : combined
        self.assetName = "WLED_\(versionWithPlatform).bin"
        _ = findAsset(assetName: assetName)
    }
    
    /// Searches the `Version`'s assets for a specific filename.
    ///
    /// - Parameter assetName: The exact filename to look for (e.g., "WLED_0.14.0_ESP32.bin").
    /// - Returns: `true` if the asset was found, `false` otherwise.
    private func findAsset(assetName: String) -> Bool {
        if let foundAsset = (version.assets as? Set<Asset>)?.first(where: { $0.name == assetName}) {
            self.asset = foundAsset
            couldDetermineAsset = true
            return true
        }
        return false
    }
    
    func getAssetName() -> String {
        return assetName
    }
    
    // MARK: - Asset Management
    
    /// Retrieves the determined asset object, if any.
    ///
    /// - Returns: The `Asset` object or `nil` if not determined.
    func getVersionAsset() -> Asset? {
        return asset
    }
    
    /// Checks if the binary file for the determined asset is already saved locally.
    ///
    /// - Returns: `true` if the file exists on the disk, `false` otherwise.
    func isAssetFileCached() -> Bool {
        guard let binaryPath = getPathForAsset() else {
            return false
        }
        return FileManager.default.fileExists(atPath: binaryPath.path)
    }
    
    /// Downloads the firmware binary from GitHub and saves it to the local cache.
    ///
    /// - Returns: `true` if the download succeeded, `false` otherwise.
    func downloadBinary() async -> Bool {
        guard let asset = asset else {
            return false
        }
        guard let localUrl = getPathForAsset() else {
            return false
        }
        
        return await getGithubApi().downloadReleaseBinary(asset: asset, targetFile: localUrl)
    }
    
    // MARK: - Installation
    
    /// Initiates the firmware update process on the device using the downloaded binary.
    ///
    /// - Parameters:
    ///   - onCompletion: Closure called when the update completes successfully.
    ///   - onFailure: Closure called if the update fails or the binary cannot be found.
    func installUpdate(onCompletion: @escaping () -> (), onFailure: @escaping () -> ()) {
        guard let binaryPath = getPathForAsset() else {
            onFailure()
            return
        }
        Task {
            // TODO: Fix device update after migration #statelessDevice
        }
    }
    
    // MARK: - File System Helpers
    
    /// Constructs the local file URL for where the asset should be stored.
    ///
    /// Structure: `.../Library/Caches/[tagName]/[assetName]`
    ///
    /// - Returns: The full `URL` to the file, or `nil` if the directory could not be created.
    func getPathForAsset() -> URL? {
        guard let cacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = cacheUrl.appendingPathComponent(version.tagName ?? "unknown", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathExtension(asset?.name ?? "unknown")
        } catch (let writeError) {
            print("error creating directory \(directory) : \(writeError)")
            return nil
        }
    }
}
