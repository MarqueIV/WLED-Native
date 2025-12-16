import Foundation
import SwiftUI
import Combine
import CoreData

let AP_MODE_MAC_ADDRESS = "00:00:00:00:00:00"

enum WebsocketStatus {
    case connected
    case connecting
    case disconnected
    
    func toString() -> String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        }
    }
}

@MainActor
class DeviceWithState: ObservableObject, Identifiable {
    
    @Published var device: Device
    @Published var stateInfo: DeviceStateInfo? = nil
    @Published var websocketStatus: WebsocketStatus = .disconnected

    nonisolated let id: String

    init(initialDevice: Device) {
        self.device = initialDevice
        self.id = initialDevice.macAddress ?? initialDevice.objectID.uriRepresentation().absoluteString
    }
    
    var isOnline: Bool {
        return websocketStatus == .connected
    }
    
    var isAPMode: Bool {
        return device.macAddress == AP_MODE_MAC_ADDRESS
    }

    // MARK: - Helper Functions

    /**
     * Get a DeviceWithState that can be used to represent a temporary WLED device in AP mode.
     * Note: Since Device is a Core Data entity, we need a context to create it.
     */
    static func getApModeDeviceWithState(context: NSManagedObjectContext) -> DeviceWithState {
        // Create a new Device entity
        // We assume this is transient and might not be saved to the persistent store immediately
        let device = Device(context: context)
        device.macAddress = AP_MODE_MAC_ADDRESS
        device.address = "4.3.2.1"

        let deviceWithState = DeviceWithState(initialDevice: device)
        deviceWithState.websocketStatus = .connected

        return deviceWithState
    }

}

// MARK: - Hashable & Equatable Conformance
extension DeviceWithState: Hashable {
    // Two instances are equal if they are the exact same object in memory
    nonisolated static func == (lhs: DeviceWithState, rhs: DeviceWithState) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Hash based on the object's unique memory address
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
