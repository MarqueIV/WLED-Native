import Foundation
import CoreData
import Combine

// TODO: This class was auto-converted from Kotlin using an AI, it needs to be verified.

@MainActor
class WebsocketClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    
    // MARK: - Properties
    
    // The state holder visible to the UI
    @Published var deviceState: DeviceWithState
    
    private let context: NSManagedObjectContext
    private var webSocketTask: URLSessionWebSocketTask?
    nonisolated let urlSession: URLSession
    private let delegateProxy: WeakSessionDelegate

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
    
    init(device: Device, context: NSManagedObjectContext) {
        self.deviceState = DeviceWithState(initialDevice: device)
        self.context = context

        let proxy = WeakSessionDelegate()
        self.delegateProxy = proxy
        self.urlSession = URLSession(
            configuration: .default,
            delegate: proxy,
            delegateQueue: OperationQueue.main
        )

        super.init()

        // Now that 'self' is fully initialized, connect the delegate
        self.delegateProxy.delegate = self
    }

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
        
        let delayTime = min(reconnectionDelay * pow(2.0, Double(retryCount)), maxReconnectionDelay)
        print("\(tag): Reconnecting to \(deviceState.device.address ?? "") in \(delayTime)s")
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delayTime * 1_000_000_000))
            if !isManuallyDisconnected && !isConnecting {
                self.retryCount += 1
                self.connect()
            }
        }
    }
    
    // MARK: - Message Handling
    
    private func listen() {
        webSocketTask?.receive { [weak self] result in
            Task {
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    await self.handleFailure(error)
                case .success(let message):
                    switch message {
                    case .string(let text):
                        await self.handleMessage(text)
                    case .data(let data):
                        // WLED mostly sends text, but good to handle data
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }

                    // Recursively listen for the next message
                    await self.listen()
                }
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
        let deviceID = self.deviceState.device.objectID
        let newName = info.info.name
        let newVersion = info.info.version ?? ""

        context.perform { [weak self] in
            guard let self = self else { return }
            guard let device = try? self.context.existingObject(with: deviceID) as? Device else {
                return
            }

            var currentBranch = device.branch ?? ""
            if currentBranch.isEmpty || currentBranch == Branch.unknown.rawValue {
                if newVersion.contains("-b") {
                    currentBranch = Branch.beta.rawValue
                } else {
                    currentBranch = Branch.stable.rawValue
                }
                device.branch = currentBranch
            }

            device.originalName = newName
            device.lastSeen = Int64(Date().timeIntervalSince1970 * 1000)

            if self.context.hasChanges {
                do {
                    try self.context.save()
                } catch {
                    print("Failed to update device in Core Data: \(error)")
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
    func sendState(_ state: WledState) {
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
                        Task {
                            print("\(self.tag): Failed to send message: \(error)")
                            await self.handleFailure(error)
                        }
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
        urlSession.invalidateAndCancel()
    }

    deinit {
        print("WebsocketClient deinit")
        urlSession.invalidateAndCancel()
    }

    // MARK: - URLSessionWebSocketDelegate
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // Jump to MainActor to update state
        Task { @MainActor in
            print("\(self.tag): WebSocket connected")
            self.deviceState.websocketStatus = .connected
            self.retryCount = 0
            self.isConnecting = false
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason"
            print("\(self.tag): WebSocket closing. Code: \(closeCode), reason: \(reasonString)")

            self.deviceState.websocketStatus = .disconnected

            if closeCode != .normalClosure && !self.isManuallyDisconnected {
                self.reconnect()
            }
        }
    }
}

// Helper to break the strong reference cycle between URLSession and WebsocketClient
class WeakSessionDelegate: NSObject, URLSessionWebSocketDelegate {
    weak var delegate: URLSessionWebSocketDelegate?

    init(_ delegate: URLSessionWebSocketDelegate? = nil) {
        self.delegate = delegate
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        delegate?.urlSession?(session, webSocketTask: webSocketTask, didOpenWithProtocol: `protocol`)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        delegate?.urlSession?(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
    }
}
