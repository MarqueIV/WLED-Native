
import SwiftUI

private struct DeviceGroupBoxStyle: GroupBoxStyle {
    var deviceColor: Color

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
        }
        .padding()
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(deviceColor.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension GroupBoxStyle where Self == DeviceGroupBoxStyle {
    static func device(color: Color) -> DeviceGroupBoxStyle {
        .init(deviceColor: color)
    }
}

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

struct DeviceListItemView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var device: DeviceWithState

    // MARK: - Actions
    var onTogglePower: (Bool) -> Void
    var onChangeBrightness: (Int) -> Void

    @State private var brightness: Double = 0.0

    var body: some View {
        GroupBox {
            HStack {
                DeviceInfoTwoRows(device: device)

                Toggle("Turn On/Off", isOn: isOnBinding)
                    .labelsHidden()
                    .frame(alignment: .trailing)
                    .tint(currentDeviceColor)
            }

            Slider(
                value: $brightness,
                in: 0.0...255.0,
                onEditingChanged: { editing in
                    // Call the brightness closure when dragging ends
                    if !editing {
                        onChangeBrightness(Int(brightness))
                    }
                }
            )
            .tint(currentDeviceColor)
        }
        .groupBoxStyle(.device(color: currentDeviceColor))
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .onAppear() {
            brightness = Double(device.stateInfo?.state.brightness ?? 0)
        }
        .onChange(of: device.stateInfo?.state.brightness) { brightness in
            self.brightness = Double(device.stateInfo?.state.brightness ?? 0)
        }
    }

    private var isOnBinding: Binding<Bool> {
        Binding(get: {
            device.stateInfo?.state.isOn ?? false
        }, set: { isOn in
            device.stateInfo?.state.isOn = isOn
            onTogglePower(isOn)
        })
    }

    private var currentDeviceColor: Color {
        // Depending on your getColor signature, you might need to handle the optional state explicitly
        let colorInt = device.device.getColor(state: device.stateInfo?.state)
        return colorFromHex(rgbValue: Int(colorInt))
    }

    func colorFromHex(rgbValue: Int, alpha: Double? = 1.0) -> Color {
        // &  binary AND operator to zero out other color values
        // >>  bitwise right shift operator
        // Divide by 0xFF because UIColor takes CGFloats between 0.0 and 1.0

        let red =   CGFloat((rgbValue & 0xFF0000) >> 16) / 0xFF
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 0xFF
        let blue =  CGFloat(rgbValue & 0x0000FF) / 0xFF
        let alpha = CGFloat(alpha ?? 1.0)

        return fixColor(color: UIColor(red: red, green: green, blue: blue, alpha: alpha))
    }

    // Fixes the color if it is too dark or too bright depending of the dark/light theme
    func fixColor(color: UIColor) -> Color {
        var h = CGFloat(0), s = CGFloat(0), b = CGFloat(0), a = CGFloat(0)
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        b = colorScheme == .dark ? fmax(b, 0.2) : fmin(b, 0.75)
        return Color(UIColor(hue: h, saturation: s, brightness: b, alpha: a))
    }
}

struct DeviceListItemView_Previews: PreviewProvider {
    static let device = DeviceWithState(
        initialDevice: Device(
            context: PersistenceController.preview.container.viewContext
        )
    )

    static var previews: some View {
        device.device.macAddress = UUID().uuidString
        device.device.originalName = ""
        device.device.address = "192.168.11.101"
        device.device.isHidden = false
        // TODO: #statelessDevice fix device preview
        //        device.isOnline = true
        //        device.networkRssi = -80
        //        device.color = 6244567779
        //        device.brightness = 125
        //        device.isRefreshing = true
        //        device.isHidden = true


        return DeviceListItemView(
            device: device,
            onTogglePower: { isOn in
                print("Preview: Power toggled to \(isOn)")
            },
            onChangeBrightness: { val in
                print("Preview: Brightness changed to \(val)")
            }
        )
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
