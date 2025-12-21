//
//  DeviceFirstContactService.swift
//  WLED
//
//  Created by Christophe Gagnier on 2025-12-16.
//

import Foundation
import CoreData
import OSLog

/// Service responsible for handling the first contact with a device.
/// It fetches device info and handles the creation or update of the Device entity in Core Data.
actor DeviceFirstContactService {

    private let persistenceController: PersistenceController
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.wled", category: "DeviceFirstContactService")

    enum ServiceError: Error {
        case invalidURL
        case missingMacAddress
        case networkError(Error)
    }

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Public API

    /// Fetches device information using its address, then ensures a corresponding
    /// device record exists in the database (creating or updating its address
    /// as necessary).
    ///
    /// - Parameter address: The network address (e.g., IP or hostname) to query.
    /// - Returns: The NSManagedObjectID of the device (to be retrieved safely on the main thread).
    func fetchAndUpsertDevice(address: String) async throws -> NSManagedObjectID {
        logger.debug("Trying to create/update device at: \(address)")

        // TODO: Sanitize URL, adding a device with a protocol (ex: http) breaks the websockets and looks weird in the UI, strip protocol.
        let info = try await getDeviceInfo(address: address)

        guard let macAddress = info.mac, !macAddress.isEmpty else {
            logger.error("Could not retrieve MAC address for device at \(address)")
            throw ServiceError.missingMacAddress
        }

        // Perform Core Data operations on a background context
        return try await persistenceController.container.performBackgroundTask { context in
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

            // Try to find existing device
            let request: NSFetchRequest<Device> = Device.fetchRequest()
            request.predicate = NSPredicate(format: "macAddress == %@", macAddress)
            request.fetchLimit = 1

            let device: Device

            if let existingDevice = try? context.fetch(request).first {
                if existingDevice.address == address && existingDevice.originalName == info.name {
                    self.logger.debug("Device already exists for MAC and is unchanged: \(macAddress)")
                    device = existingDevice
                } else {
                    self.logger.debug("Device already exists for MAC but is different: \(macAddress). Updating.")
                    existingDevice.address = address
                    existingDevice.originalName = info.name
                    device = existingDevice
                }
            } else {
                self.logger.debug("No existing device found for MAC: \(macAddress). Creating new entry.")
                device = Device(context: context)
                device.macAddress = macAddress
                device.address = address
                device.originalName = info.name
                device.isHidden = false
                // Initialize other default properties if needed
            }

            if context.hasChanges {
                try context.save()
            }

            return device.objectID
        }
    }

    /// Attempts to identify and update a device using only the MAC address from mDNS/Discovery.
    /// This avoids a network call to the device if we already know who it is.
    ///
    /// - Parameters:
    ///   - macAddress: The MAC address found via mDNS (can be null/empty).
    ///   - address: The new IP address.
    /// - Returns: true if the device was found and processed (updated or skipped), false otherwise.
    func tryUpdateAddress(macAddress: String?, address: String) async -> Bool {
        guard let macAddress, !macAddress.isEmpty else {
            return false
        }

        return await persistenceController.container.performBackgroundTask { context in
            let request: NSFetchRequest<Device> = Device.fetchRequest()
            request.predicate = NSPredicate(format: "macAddress == %@", macAddress)
            request.fetchLimit = 1

            guard let existingDevice = try? context.fetch(request).first else {
                return false
            }

            if existingDevice.address != address {
                self.logger.info("Fast update: IP changed for \(existingDevice.originalName ?? "Unknown") (\(macAddress))")
                existingDevice.address = address

                do {
                    try context.save()
                } catch {
                    self.logger.error("Failed to save fast update: \(error.localizedDescription)")
                }
            } else {
                self.logger.debug("Fast update: Device IP unchanged for \(macAddress)")
            }

            return true
        }
    }

    // MARK: - Private Helpers

    /// Fetches device information from the specified address.
    private func getDeviceInfo(address: String) async throws -> Info {
        // Construct URL, ensuring http scheme and json/info path
        var urlString = address
        if !urlString.lowercased().hasPrefix("http") {
            urlString = "http://\(address)"
        }

        // Remove trailing slash if present before appending path
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }

        guard let url = URL(string: "\(urlString)/json/info") else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0 // Short timeout for discovery checks
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let info = try JSONDecoder().decode(Info.self, from: data)
            return info
        } catch {
            throw ServiceError.networkError(error)
        }
    }
}
