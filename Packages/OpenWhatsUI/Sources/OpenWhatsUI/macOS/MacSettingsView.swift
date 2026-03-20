#if os(macOS)
import SwiftUI
import OpenWhatsCore

/// macOS Preferences window — shown via ⌘, or Settings menu.
public struct MacSettingsView: View {

    public init() {}

    public var body: some View {
        TabView {
            MacGeneralSettings()
                .tabItem { Label("General", systemImage: "gear") }
                .tag("general")

            MacNotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
                .tag("notifications")

            MacLinkedDevicesView()
                .tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }
                .tag("devices")
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General

private struct MacGeneralSettings: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDockBadge")  private var showDockBadge  = true

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Toggle("Show Unread Badge in Dock", isOn: $showDockBadge)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Notifications

private struct MacNotificationSettings: View {
    @AppStorage("notifySounds") private var notifySounds = true
    @AppStorage("notifyBanner") private var notifyBanner = true

    var body: some View {
        Form {
            Toggle("Message Sounds", isOn: $notifySounds)
            Toggle("Show Banners", isOn: $notifyBanner)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Linked Devices

struct MacLinkedDevicesView: View {

    @State private var devices: [DeviceInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDevice: DeviceInfo?

    private let myDeviceID = AccountManager.shared.deviceID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red).padding()
            } else {
                Table(devices) {
                    TableColumn("Type") { device in
                        Label(device.deviceType == "phone" ? "iPhone" : "Mac",
                              systemImage: device.deviceType == "phone" ? "iphone" : "laptopcomputer")
                    }
                    .width(100)
                    TableColumn("Status") { device in
                        if device.deviceId == myDeviceID {
                            Text("This device").foregroundStyle(Color.owGreen)
                        } else if let seen = device.lastSeenAt {
                            Text(seen.relativeString).foregroundStyle(.secondary)
                        } else {
                            Text("Never seen").foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Added") { device in
                        Text(device.createdAt.relativeString)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    Button("Refresh") { Task { await loadDevices() } }
                    Spacer()
                    Button("Remove Device", role: .destructive) {
                        if let d = selectedDevice { Task { await removeDevice(d) } }
                    }
                    .disabled(selectedDevice == nil || selectedDevice?.deviceId == myDeviceID)
                }
                .padding(10)
            }
        }
        .task { await loadDevices() }
    }

    private func loadDevices() async {
        isLoading = true; errorMessage = nil
        do {
            devices = try await APIClient.shared.listDevices().devices
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func removeDevice(_ device: DeviceInfo) async {
        do {
            try await APIClient.shared.deleteDevice(deviceID: device.deviceId)
            devices.removeAll { $0.deviceId == device.deviceId }
            selectedDevice = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    MacSettingsView()
}
#endif
