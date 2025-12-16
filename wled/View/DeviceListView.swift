
import SwiftUI
import CoreData


struct DeviceListView: View {

    // MARK: - Properties

    @StateObject private var viewModel: DeviceWebsocketListViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: DeviceWithState? = nil
    @State private var addDeviceButtonActive: Bool = false

    @SceneStorage("DeviceListView.showHiddenDevices") private var showHiddenDevices: Bool = false
    @SceneStorage("DeviceListView.showOfflineDevices") private var showOfflineDevices: Bool = true

    private let discoveryService = DiscoveryService()

    init() {
        // Inject the view context into the ViewModel
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: DeviceWebsocketListViewModel(context: context))
    }

    // MARK: - Computed Data

    private var onlineDevices: [DeviceWithState] {
        viewModel.allDevicesWithState.filter { deviceWrapper in
            deviceWrapper.isOnline && (showHiddenDevices || !deviceWrapper.device.isHidden)
        }
        .sorted { $0.device.displayName < $1.device.displayName }
    }

    private var offlineDevices: [DeviceWithState] {
        viewModel.allDevicesWithState.filter { deviceWrapper in
            !deviceWrapper.isOnline && (showHiddenDevices || !deviceWrapper.device.isHidden)
        }
        .sorted { $0.device.displayName < $1.device.displayName }
    }

    //MARK: - Body

    var body: some View {
        NavigationSplitView {
            list
                .toolbar{ toolbar }
                .sheet(isPresented: $addDeviceButtonActive, content: DeviceAddView.init)
                .navigationBarTitleDisplayMode(.inline)
        } detail: {
            detailView
        }
        .onAppear(perform: appearAction)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                viewModel.onResume()
            case .background, .inactive:
                viewModel.onPause()
            @unknown default:
                break
            }
        }
    }
    
    var list: some View {
        List(selection: $selection) {
            if !onlineDevices.isEmpty {
                Section(header: Text("Online Devices")) {
                    deviceRows(for: onlineDevices)
                }
            } else if !showOfflineDevices && offlineDevices.isEmpty {
                // Empty state hint could go here
            }

            // Offline Devices
            if !offlineDevices.isEmpty && showOfflineDevices {
                Section(header: Text("Offline Devices")) {
                    deviceRows(for: offlineDevices)
                }
            }
        }
        .listStyle(.plain)
        .refreshable(action: refreshList)
    }

    @ViewBuilder
    private func deviceRows(for devices: [DeviceWithState]) -> some View {
        ForEach(devices) { device in
            DeviceListItemView()
                .overlay(
                    // Invisible NavigationLink to handle selection while preserving custom row interactions
                    NavigationLink("", value: device).opacity(0)
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .buttonStyle(PlainButtonStyle())
                .environmentObject(device)
                .swipeActions(allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteItems(device: device.device)
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                    }
                }
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        if let device = selection {
            NavigationStack {
                DeviceView()
                    .environmentObject(device)
            }
        } else {
            Text("Select A Device")
                .font(.title2)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack {
                Image(.wledLogoAkemi)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
            .frame(maxWidth: 200)
        }
        ToolbarItem {
            Menu {
                Section {
                    addButton
                }
                Section {
                    visibilityButton
                    hideOfflineButton
                }
                Section {
                    Link(destination: URL(string: "https://kno.wled.ge/")!) {
                        Label("WLED Documentation", systemImage: "questionmark.circle")
                    }
                }
            } label: {
                Label("Menu", systemImage: "ellipsis.circle")
            }
        }
    }
    
    var addButton: some View {
        Button {
            addDeviceButtonActive.toggle()
        } label: {
            Label("Add New Device", systemImage: "plus")
        }
    }
    
    var visibilityButton: some View {
        Button {
            withAnimation {
                showHiddenDevices.toggle()
            }
        } label: {
            if (showHiddenDevices) {
                Label("Hide Hidden Devices", systemImage: "eye.slash")
            } else {
                Label("Show Hidden Devices", systemImage: "eye")
            }
        }
    }
    
    var hideOfflineButton: some View {
        Button {
            withAnimation {
                showOfflineDevices.toggle()
            }
        } label: {
            if (showOfflineDevices) {
                Label("Hide Offline Devices", systemImage: "wifi")
            } else {
                Label("Show Offline Devices", systemImage: "wifi.slash")
            }
        }
    }
    
    //MARK: - Actions
    
    @Sendable
    private func refreshList() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await discoveryService.scan() }
        }
        viewModel.refreshOfflineDevices()
    }

    private func appearAction() {
        viewModel.onResume()
        discoveryService.scan()
    }
    
    private func deleteItems(device: Device) {
        withAnimation {
            viewModel.deleteDevice(device)
        }
    }
}


struct DeviceListView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceListView()
        // In preview, the persistence controller singleton is used by default in init,
        // but for previews we often want the in-memory version.
        // Since we use Singleton access in init(), we ensure shared is set up for previews
        // or mock it if needed. The provided PersistenceController has a static preview.
    }
}
