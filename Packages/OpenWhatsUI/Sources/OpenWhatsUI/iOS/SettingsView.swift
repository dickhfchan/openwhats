#if os(iOS)
import SwiftUI
import OpenWhatsCore

public struct SettingsView: View {

    @State private var displayName = "Me"
    @State private var handle = "myhandle"
    @State private var showLinkedDevices = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    HStack(spacing: 14) {
                        AvatarView(url: nil, name: displayName, size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName)
                                .font(.system(size: 18, weight: .semibold))
                            Text("@\(handle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.vertical, 6)
                }

                // Settings sections
                Section("Notifications") {
                    NavigationLink {
                        Text("Notification settings")
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                }

                Section("Privacy") {
                    NavigationLink {
                        Text("Privacy settings")
                    } label: {
                        Label("Privacy", systemImage: "hand.raised.fill")
                    }
                }

                Section("Account") {
                    NavigationLink {
                        LinkedDevicesView()
                    } label: {
                        Label("Linked Devices", systemImage: "laptopcomputer.and.iphone")
                    }
                    NavigationLink {
                        Text("Storage and data")
                    } label: {
                        Label("Storage and Data", systemImage: "internaldrive")
                    }
                }

                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { @MainActor in performSignOut() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Linked Devices

private struct LinkedDevicesView: View {

    @State private var devices: [DeviceInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deviceToRemove: DeviceInfo?

    private let myDeviceID = AccountManager.shared.deviceID

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.footnote)
            } else {
                // This device
                if let mine = devices.first(where: { $0.deviceId == myDeviceID }) {
                    Section {
                        DeviceRow(device: mine, isCurrentDevice: true)
                    }
                }

                // Other linked devices
                let others = devices.filter { $0.deviceId != myDeviceID }
                if others.isEmpty {
                    Section("Linked Desktop") {
                        ContentUnavailableView(
                            "No Mac linked",
                            systemImage: "laptopcomputer.slash",
                            description: Text("Sign in with the same Apple ID on your Mac.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Linked Devices") {
                        ForEach(others) { device in
                            DeviceRow(device: device, isCurrentDevice: false)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deviceToRemove = device
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Linked Devices")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDevices() }
        .refreshable { await loadDevices() }
        .confirmationDialog(
            "Remove device?",
            isPresented: Binding(get: { deviceToRemove != nil }, set: { if !$0 { deviceToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let d = deviceToRemove { Task { await removeDevice(d) } }
            }
        } message: {
            Text("This will sign out the linked device. You cannot undo this.")
        }
    }

    private func loadDevices() async {
        isLoading = true
        errorMessage = nil
        do {
            let resp = try await APIClient.shared.listDevices()
            devices = resp.devices
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func removeDevice(_ device: DeviceInfo) async {
        do {
            try await APIClient.shared.deleteDevice(deviceID: device.deviceId)
            devices.removeAll { $0.deviceId == device.deviceId }
        } catch {
            errorMessage = error.localizedDescription
        }
        deviceToRemove = nil
    }
}

private struct DeviceRow: View {
    let device: DeviceInfo
    let isCurrentDevice: Bool

    private var icon: String {
        device.deviceType == "phone" ? "iphone" : "laptopcomputer"
    }

    private var typeName: String {
        device.deviceType == "phone" ? "iPhone" : "Mac"
    }

    private var subtitle: String {
        if isCurrentDevice { return "This device" }
        if let seen = device.lastSeenAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            return "Last active " + f.localizedString(for: seen, relativeTo: Date())
        }
        return "Added " + device.createdAt.relativeString
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(typeName)
                    .font(.system(size: 16, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(isCurrentDevice ? Color.owGreen : .secondary)
        }
    }
}

#Preview {
    SettingsView()
}
#endif
