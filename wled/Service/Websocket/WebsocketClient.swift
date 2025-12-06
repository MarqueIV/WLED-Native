import Foundation
import CoreData
import Combine

// TODO: This class was auto-converted from Kotlin using an AI, it needs to be verified.

class WebsocketClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    
    // MARK: - Properties
    
    // The state holder visible to the UI
    @Published var deviceState: DeviceWithState
    
    private let context: NSManagedObjectContext
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    
    // State flags
    private var isManuallyDisconnected = false
    private var isConnecting = false
    private var retryCount = 0
    
    // Constants
    private let tag = "WebsocketClient"
    private let reconnectionDelay: TimeInterval = 2.5
    private let maxReconnectionDelay: TimeInterval = 60.0
    
    // Coders
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    // MARK: - Initialization
    
    init(device: Device2, context: NSManagedObjectContext) {
        self.deviceState = DeviceWithState(initialDevice: device)
        self.context = context
        
        // Create a session configuration
        let config = URLSessionConfiguration.default
        // Create the session. We set 'self' as delegate to handle open/close events
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: OperationQueue())
        
        super.init()
        
        // We need to set the delegate after super.init, but session is immutable.
        // URLSession(configuration:delegate:delegateQueue:) works, but we need to pass 'self'.
        // To strictly satisfy Swift init rules, we often use a lazy var or configure a separate session coordinator.
        // However, for this implementation, we will assign the delegate via the session creation if possible or just rely on the task callbacks for errors and completion.
        // Note: URLSession holds a strong reference to delegate, so be careful with retain cycles if not careful.
        // Re-creating the session to set the delegate:
    }
    
    // Lazy session loader to allow 'self' as delegate
    private lazy var urlSession: URLSession = {
        return URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
    }()
    
    // MARK: - Connection Logic
    
    func connect() {
        if webSocketTask != nil || isConnecting {
            print("\(tag): Already connected or connecting to \(deviceState.device.address ?? "nil")")
            return
        }
        
        guard let address = deviceState.device.address, !address.isEmpty else {
            print("\(tag): Device address is empty")
            return
        }
        
        isManuallyDisconnected = false
        isConnecting = true
        
        DispatchQueue.main.async {
            self.deviceState.websocketStatus = .connecting
        }
        
        let urlString = "ws://\(address)/ws"
        guard let url = URL(string: urlString) else {
            print("\(tag): Invalid URL \(urlString)")
            return
        }
        
        print("\(tag): Connecting to \(address)")
        let request = URLRequest(url: url)
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start listening for messages
        listen()
    }
    
    func disconnect() {
        print("\(tag): Manually disconnecting from \(deviceState.device.address ?? "")")
        isManuallyDisconnected = true
        
        webSocketTask?.cancel(with: .normalClosure, reason: "Client disconnected".data(using: .utf8))
        webSocketTask = nil
        
        DispatchQueue.main.async {
            self.deviceState.websocketStatus = .disconnected
            self.isConnecting = false
        }
    }
    
    private func reconnect() {
        if isManuallyDisconnected || isConnecting { return }
        
        let delayTime = min(
            reconnectionDelay * pow(2.0, Double(retryCount)),
            maxReconnectionDelay
        )
        
        print("\(tag): Reconnecting to \(deviceState.device.address ?? "") in \(delayTime)s")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + delayTime) { [weak self] in
            guard let self = self else { return }
            self.retryCount += 1
            self.connect()
        }
    }
    
    // MARK: - Message Handling
    
    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                self.handleFailure(error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    // WLED mostly sends text, but good to handle data
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Recursively listen for the next message
                self.listen()
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        // print("\(tag): onMessage: \(text)") // Uncomment for verbose logging
        
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let info = try decoder.decode(DeviceStateInfo.self, from: data)
            
            // Update UI State on Main Thread
            DispatchQueue.main.async {
                self.deviceState.stateInfo = info
                
                // If we get a message, we are connected (fallback if onOpen didn't fire)
                if self.isConnecting {
                    // This logic is usually handled in urlSession(_:webSocketTask:didOpenWithProtocol:)
                    // but can be reinforced here.
                }
            }
            
            // Update Core Data Entity
            updateDeviceEntity(with: info)
            
        } catch {
            print("\(tag): Failed to parse JSON from WebSocket: \(error)")
        }
    }
    
    private func updateDeviceEntity(with info: DeviceStateInfo) {
        context.perform { [weak self] in
            guard let self = self else { return }
            let device = self.deviceState.device
            
            // Branch detection logic
            var currentBranch = device.branch ?? ""
            if currentBranch.isEmpty || currentBranch == Branch.unknown.rawValue {
                let version = info.info.version ?? ""
                if version.contains("-b") {
                    currentBranch = Branch.beta.rawValue
                } else {
                    currentBranch = Branch.stable.rawValue
                }
                device.branch = currentBranch
            }
            
            // Update other fields
            device.originalName = info.info.name
            // device.address is already set
            device.lastSeen = Int64(Date().timeIntervalSince1970 * 1000)
            
            // Save if changes exist
            if self.context.hasChanges {
                do {
                    try self.context.save()
                } catch {
                    print("\(self.tag): Failed to update device in Core Data: \(error)")
                }
            }
        }
    }
    
    private func handleFailure(_ error: Error) {
        print("\(tag): WebSocket failure: \(error)")
        webSocketTask = nil
        
        DispatchQueue.main.async {
            self.deviceState.websocketStatus = .disconnected
            self.isConnecting = false
        }
        
        reconnect()
    }
    
    // MARK: - Sending
    
    /// Sends a State object to the device.
    /// Note: Kotlin code used `State` class. In Swift, assuming `WLEDStateChange` or `WledState` is the equivalent Encodable struct.
    func sendState(_ state: WLEDStateChange) {
        if deviceState.websocketStatus != .connected {
            print("\(tag): Not connected to \(deviceState.device.address ?? ""), reconnecting...")
            connect()
        }
        
        do {
            let data = try encoder.encode(state)
            if let jsonString = String(data: data, encoding: .utf8) {
                print("\(tag): Sending message: \(jsonString)")
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                
                webSocketTask?.send(message) { error in
                    if let error = error {
                        print("\(self.tag): Failed to send message: \(error)")
                        self.handleFailure(error)
                    }
                }
            }
        } catch {
            print("\(tag): Failed to encode state: \(error)")
        }
    }
    
    func destroy() {
        print("\(tag): Websocket client destroyed")
        disconnect()
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("\(tag): WebSocket connected for \(deviceState.device.address ?? "")")
        
        DispatchQueue.main.async {
            self.deviceState.websocketStatus = .connected
            self.retryCount = 0
            self.isConnecting = false
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason"
        print("\(tag): WebSocket closing. Code: \(closeCode), Reason: \(reasonString)")
        
        DispatchQueue.main.async {
            self.deviceState.websocketStatus = .disconnected
        }
        
        // If it wasn't a normal closure initiated by us, try to reconnect
        if closeCode != .normalClosure && !isManuallyDisconnected {
            reconnect()
        }
    }
}
