import Foundation
import SwiftUI
import Combine
import CoreData

let AP_MODE_MAC_ADDRESS = "00:00:00:00:00:00"

enum WebsocketStatus {
    case connected
    case connecting
    case disconnected
}

class DeviceWithState: ObservableObject, Identifiable {
    
    @Published var device: Device2
    @Published var stateInfo: DeviceStateInfo? = nil
    @Published var websocketStatus: WebsocketStatus = .disconnected
    
    init(initialDevice: Device2) {
        self.device = initialDevice
    }
    
    // MARK: - Identifiable Conformance
    // We use the MAC address as the stable ID.
    // If MAC is missing (e.g. new device not yet polled), we fallback to the CoreData ObjectID which is always unique.
    var id: String {
        return device.macAddress ?? device.objectID.uriRepresentation().absoluteString
    }
    
    var isOnline: Bool {
        return websocketStatus == .connected
    }
    
    var isAPMode: Bool {
        return device.macAddress == AP_MODE_MAC_ADDRESS
    }
}

// MARK: - Hashable & Equatable Conformance
extension DeviceWithState: Hashable {
    // Two instances are equal if they are the exact same object in memory
    static func == (lhs: DeviceWithState, rhs: DeviceWithState) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Hash based on the object's unique memory address
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Helper Functions

/**
 * Get a DeviceWithState that can be used to represent a temporary WLED device in AP mode.
 * Note: Since Device2 is a Core Data entity, we need a context to create it.
 */
func getApModeDeviceWithState(context: NSManagedObjectContext) -> DeviceWithState {
    // Create a new Device2 entity
    // We assume this is transient and might not be saved to the persistent store immediately
    let device = Device2(context: context)
    device.macAddress = AP_MODE_MAC_ADDRESS
    device.address = "4.3.2.1"
    
    let deviceWithState = DeviceWithState(initialDevice: device)
    deviceWithState.websocketStatus = .connected
    
    return deviceWithState
}
