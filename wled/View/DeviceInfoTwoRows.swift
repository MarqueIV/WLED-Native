//
//  DeviceInfoTwoRows.swift
//  WLED
//
//  Created by Christophe Gagnier on 2025-12-16.
//


import SwiftUI

struct DeviceInfoTwoRows: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var device: DeviceWithState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(device.device.displayName)
                    .font(.headline.leading(.tight))
                    .lineLimit(2)
                // TODO: #statelessDevice migration implement proper Websocket status indicator
                Text(device.websocketStatus.toString())
                if hasUpdateAvailable() {
                    Image(systemName: getUpdateIconName())
                }
            }
            HStack {
                Text(device.device.address ?? "")
                    .lineLimit(1)
                    .fixedSize()
                    .font(.subheadline.leading(.tight))
                    .lineSpacing(0)
                Image(uiImage: getSignalImage(isOnline: device.isOnline, signalStrength: Int(device.stateInfo?.info.wifi.signal ?? 0)))
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.primary)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 12)
                if (!device.isOnline) {
                    Text("(Offline)")
                        .lineLimit(1)
                        .font(.subheadline.leading(.tight))
                        .foregroundStyle(.secondary)
                        .lineSpacing(0)
                }
                if (device.device.isHidden) {
                    Image(systemName: "eye.slash")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.secondary)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 12)
                    Text("(Hidden)")
                        .lineLimit(1)
                        .font(.subheadline.leading(.tight))
                        .foregroundStyle(.secondary)
                        .lineSpacing(0)
                        .truncationMode(.tail)
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func hasUpdateAvailable() -> Bool {
        viewContext.performAndWait {
            // TODO: #statelessDevice migration fix hasUpdateAvailable
            return !(/*device.latestUpdateVersionTagAvailable ?? */"").isEmpty
        }
    }

    func getUpdateIconName() -> String {
        if #available(iOS 17.0, *) {
            return "arrow.down.circle.dotted"
        } else {
            return "arrow.down.circle"
        }
    }

    func getSignalImage(isOnline: Bool, signalStrength: Int?) -> UIImage {
        let icon = !isOnline || signalStrength == nil || signalStrength == 0 ? "wifi.slash" : "wifi"
        var image: UIImage;
        if #available(iOS 16.0, *) {
            image = UIImage(
                systemName: icon,
                variableValue: getSignalValue(signalStrength: signalStrength)
            )!
        } else {
            image = UIImage(
                systemName: icon
            )!
        }
        image.applyingSymbolConfiguration(UIImage.SymbolConfiguration(hierarchicalColor: .systemBlue))
        return image
    }

    func getSignalValue(signalStrength: Int?) -> Double {
        if let signalStrength {
            if (signalStrength >= -70) {
                return 1
            }
            if (signalStrength >= -85) {
                return 0.64
            }
            if (signalStrength >= -100) {
                return 0.33
            }
        }
        return 0
    }
}