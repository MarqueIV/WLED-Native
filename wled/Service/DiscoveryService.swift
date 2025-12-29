
import Foundation
import Combine
import CoreData
import Network
import SwiftUI

// TODO: Check if this needs a start/stop like on Android
class DiscoveryService: NSObject, Identifiable {

    let onDeviceDiscovered: (_ address: String, _ macAddress: String?) -> Void
    var browser: NWBrowser!

    init(onDeviceDiscovered: @escaping (_: String, _: String?) -> Void) {
        self.onDeviceDiscovered = onDeviceDiscovered
    }

    // TODO: Check if the `scan` function can be improved (mostly for readability)
    func scan() {
        let bonjourTCP = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_wled._tcp" , domain: "local.")

        let bonjourParms = NWParameters()
        bonjourParms.allowLocalEndpointReuse = true
        bonjourParms.acceptLocalOnly = true
        bonjourParms.allowFastOpen = true
        
        browser = NWBrowser(for: bonjourTCP, using: bonjourParms)
        browser.stateUpdateHandler = {newState in
            switch newState {
            case .failed(let error):
                print("NW Browser: now in Error state: \(error)")
                self.browser.cancel()
            case .ready:
                print("NW Browser: new bonjour discovery - ready")
            case .setup:
                print("NW Browser: in SETUP state")
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { ( results, changes ) in
            print("NW Browser: Scan results found:")
            for result in results {
                print(result.endpoint.debugDescription)
            }
            for change in changes {
                if case .added(let result) = change {

                    var macAddress: String?
                    if case .bonjour(let txtRecord) = result.metadata {
                        macAddress = txtRecord["mac"]
                    }
                    print("NW Browser: Added, mac: \(macAddress?.description ?? "nil")")
                    if case .service(let name, _, _, _) = result.endpoint {
                        print("Connecting to \(name), MAC: \(macAddress?.description ?? "nil")")
                        let connection = NWConnection(to: result.endpoint, using: .tcp)
                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                                   case .hostPort(let host, let port) = innerEndpoint {
                                    let remoteHost = "\(host)".split(separator: "%")[0]
                                    print("Connected to \(name) at", "\(remoteHost):\(port)")
                                    self.onDeviceDiscovered("\(remoteHost)", macAddress)
                                }
                            default:
                                break
                            }
                        }
                        connection.start(queue: .global())
                    }
                }
            }
        }
        self.browser.start(queue: DispatchQueue.main)
    }
}
