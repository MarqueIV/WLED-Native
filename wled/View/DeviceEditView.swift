
import SwiftUI

struct DeviceEditView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    
    @ObservedObject var device: DeviceWithState

    enum Field {
        case name
    }
    
    @State private var address: String = ""
    @State private var customName: String = ""
    @State private var hideDevice: Bool = false
    @State private var branch = ""
    @State private var isFormValid: Bool = true
    @State private var isCheckingForUpdates: Bool = false
    @FocusState var isNameFieldFocused: Bool
    
    let unknownVersion = String(localized: "unknown_version")
    var branchOptions = ["Stable", "Beta"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("IP Address or URL")
                TextField("IP Address or URL", text: $address)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(true)
            }
            
            VStack(alignment: .leading) {
                Text("Custom Name")
                TextField("Custom Name", text: $customName)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: isNameFieldFocused) { isFocused in
                        if (!isFocused) {
                            device.device.customName = customName
                            saveDevice()
                        }
                    }
            }
            
            Toggle("Hide this Device", isOn: $hideDevice)
                .onChange(of: hideDevice) { newValue in
                    device.device.isHidden = newValue
                    saveDevice()
                }
                .padding(.trailing, 2)
                .padding(.bottom)
            
            HStack {
                Text("Update Channel")
                Spacer()
                Picker("Update Channel", selection: $branch) {
                    ForEach(branchOptions, id: \.self) {
                        Text(LocalizedStringKey($0))
                            .padding()
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: branch) { newValue in
                    let newBranch = newValue == "Beta" ? Branch.beta : Branch.stable
                    if newBranch == device.device.branchValue {
                        return
                    }
                    // TODO: Updating the device in the database should probably
                    //   be done in a viewmodel
                    device.device.branchValue = newBranch
                    device.device.skipUpdateTag = ""
                    saveDevice()
                }
            }
            .padding(.bottom)

            if (device.stateInfo != nil) {
                // TODO: Update this to be its own "helicopter" view
                VStack(alignment: .leading) {
                    if ((device.availableUpdateVersion ?? "").isEmpty) {
                        Text("Your device is up to date")
                        Text(
                            "Version \(device.stateInfo?.info.version ?? unknownVersion)"
                        )
                        HStack {
                            Button(action: {
                                Task {
                                    await checkForUpdate()
                                }
                            }) {
                                Text(isCheckingForUpdates ? "Checking for Updates" : "Check for Update")
                            }
                            .buttonStyle(.bordered)
                            .padding(.trailing)
                            .disabled(isCheckingForUpdates)
                            ProgressView()
                                .opacity(isCheckingForUpdates ? 1 : 0)
                        }
                    } else {
                        HStack {
                            Image(systemName: getUpdateIconName())
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 30.0, height: 30.0)
                                .padding(.trailing)
                            VStack(alignment: .leading) {
                                Text("Update Available")
                                Text("From \(device.stateInfo?.info.version ?? unknownVersion) to \(device.availableUpdateVersion ?? unknownVersion)")
                                NavigationLink {
                                    DeviceUpdateDetails(device: device)
                                } label: {
                                    Text("See Update")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .animation(.default, value: device.availableUpdateVersion)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Edit Device")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear() {
            address = device.device.address ?? ""
            customName = device.device.customName ?? ""
            hideDevice = device.device.isHidden
            branch = device.device.branchValue == Branch.beta ? "Beta" : "Stable"
        }
    }
    
    private func saveDevice() {
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func checkForUpdate() async {
        withAnimation {
            isCheckingForUpdates = true
        }
        print("Refreshing available Releases")
        await ReleaseService(context: viewContext).refreshVersions()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: WLEDNativeApp.dateLastUpdateKey)
        
        device.device.skipUpdateTag = ""
        withAnimation {
            Task {
                // TODO: #statelessDevice migration fix this?
                // await device.requestManager.addRequest(WLEDRefreshRequest(context: viewContext))
            }
            isCheckingForUpdates = false
        }
    }
    
    func getUpdateIconName() -> String {
        if #available(iOS 17.0, *) {
            return "arrow.down.circle.dotted"
        } else {
            return "arrow.down.circle"
        }
    }
}

struct DeviceEditView_Previews: PreviewProvider {
    static let device = DeviceWithState(
        initialDevice: Device(
            context: PersistenceController.preview.container.viewContext
        )
    )

    static var previews: some View {
        device.device.macAddress = UUID().uuidString
        device.device.originalName = "Original name"
        device.device.customName = "A custom name"
        device.device.address = "192.168.11.101"
        device.device.isHidden = true

        
        return DeviceEditView(device: device)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
