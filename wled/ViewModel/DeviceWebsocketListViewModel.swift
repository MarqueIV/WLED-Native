import Foundation
import CoreData
import Combine
import SwiftUI

// TODO: This class was auto-converted from Kotlin using an AI, it needs to be verified.

class DeviceWebsocketListViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    
    // MARK: - Published Properties
    
    // The list of devices with their live state, exposed to the UI
    @Published var allDevicesWithState: [DeviceWithState] = []
    
    // Preferences (You can wrap these in AppStorage or standard UserDefaults in the View)
    @Published var showOfflineDevicesLast: Bool = false
    @Published var showHiddenDevices: Bool = false
    
    // MARK: - Private Properties
    
    private let context: NSManagedObjectContext
    private var frc: NSFetchedResultsController<Device2>!
    
    // Map of MacAddress -> Client Wrapper
    // We store the last known address to detect IP changes
    private struct ClientWrapper {
        let client: WebsocketClient
        let lastKnownAddress: String
    }
    
    private var activeClients: [String: ClientWrapper] = [:]
    private var isPaused = false
    
    // MARK: - Initialization
    
    init(context: NSManagedObjectContext) {
        self.context = context
        super.init()
        
        setupFetchedResultsController()
        
        // Initial population of clients
        try? frc.performFetch()
        if let objects = frc.fetchedObjects {
            updateClients(with: objects)
        }
        
        // Load preferences (Mocked for now, replace with your UserPreferences logic)
        self.showOfflineDevicesLast = UserDefaults.standard.bool(forKey: "showOfflineDevicesLast")
        self.showHiddenDevices = UserDefaults.standard.bool(forKey: "showHiddenDevices")
    }
    
    // MARK: - Core Data Setup
    
    private func setupFetchedResultsController() {
        let request = NSFetchRequest<Device2>(entityName: "Device2")
        // Sort by lastSeen or name as a default
        request.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
        
        frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        frc.delegate = self
    }
    
    // MARK: - Client Management Logic
    
    private func updateClients(with devices: [Device2]) {
        let newDeviceMap = Dictionary(uniqueKeysWithValues: devices.compactMap { device -> (String, Device2)? in
            guard let mac = device.macAddress else { return nil }
            return (mac, device)
        })
        
        // 1. Identify and destroy clients for devices that are no longer present
        let currentMacs = Set(activeClients.keys)
        let newMacs = Set(newDeviceMap.keys)
        let macsToRemove = currentMacs.subtracting(newMacs)
        
        for mac in macsToRemove {
            print("[ListVM] Device removed: \(mac). Destroying client.")
            activeClients[mac]?.client.destroy()
            activeClients[mac] = nil
        }
        
        // 2. Identify and create/update clients for new or changed devices
        for (mac, device) in newDeviceMap {
            let address = device.address ?? ""
            
            if let existingWrapper = activeClients[mac] {
                if existingWrapper.lastKnownAddress != address {
                    // Address changed: Reconnect
                    print("[ListVM] Address changed for \(mac). Recreating client.")
                    existingWrapper.client.destroy()
                    createAndAddClient(for: device, mac: mac)
                } else {
                    // Just a regular update (e.g. name changed), the ObservableObject DeviceWithState handles this automatically
                    // because it holds the reference to the Core Data object.
                }
            } else {
                // New Device
                print("[ListVM] Device added: \(mac). Creating client.")
                createAndAddClient(for: device, mac: mac)
            }
        }
        
        publishState()
    }
    
    private func createAndAddClient(for device: Device2, mac: String) {
        let newClient = WebsocketClient(device: device, context: context)
        
        if !isPaused {
            newClient.connect()
        }
        
        activeClients[mac] = ClientWrapper(
            client: newClient,
            lastKnownAddress: device.address ?? ""
        )
    }
    
    private func publishState() {
        // Map the clients to the DeviceWithState list expected by the UI
        DispatchQueue.main.async {
            self.allDevicesWithState = self.activeClients.values.map { wrapper in
                wrapper.client.deviceState
            }
        }
    }
    
    // MARK: - NSFetchedResultsControllerDelegate
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        guard let devices = controller.fetchedObjects as? [Device2] else { return }
        updateClients(with: devices)
    }
    
    // MARK: - Lifecycle (Call these from App ScenePhase)
    
    func onPause() {
        print("[ListVM] onPause: Pausing all connections.")
        isPaused = true
        activeClients.values.forEach { $0.client.disconnect() }
    }
    
    func onResume() {
        print("[ListVM] onResume: Resuming all connections.")
        isPaused = false
        activeClients.values.forEach { $0.client.connect() }
    }
    
    // MARK: - Actions
    
    func refreshOfflineDevices() {
        print("[ListVM] Refreshing offline devices.")
        let offlineClients = activeClients.values.filter { !$0.client.deviceState.isOnline }
        offlineClients.forEach { $0.client.connect() }
    }
    
    func setBrightness(for deviceWrapper: DeviceWithState, brightness: Int) {
        guard let mac = deviceWrapper.device.macAddress,
              let wrapper = activeClients[mac] else {
            print("[ListVM] No active client for \(deviceWrapper.device.macAddress ?? "nil")")
            return
        }
        
        // Assuming WLEDStateChange is your Codable struct for JSON API
        var state = WLEDStateChange()
        state.brightness = Int64(brightness)
        wrapper.client.sendState(state)
    }
    
    func setDevicePower(for deviceWrapper: DeviceWithState, isOn: Bool) {
        guard let mac = deviceWrapper.device.macAddress,
              let wrapper = activeClients[mac] else {
            print("[ListVM] No active client for \(deviceWrapper.device.macAddress ?? "nil")")
            return
        }
        
        var state = WLEDStateChange()
        state.isOn = isOn
        wrapper.client.sendState(state)
    }
    
    func deleteDevice(_ device: Device2) {
        print("[ListVM] Deleting device \(device.originalName ?? "")")
        context.perform {
            self.context.delete(device)
            try? self.context.save()
        }
    }
    
    // Cleanup
    deinit {
        activeClients.values.forEach { $0.client.destroy() }
    }
}
