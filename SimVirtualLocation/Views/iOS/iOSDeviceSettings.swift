//
//  iOSDeviceSettings.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 18.04.2022.
//

import SwiftUI

private enum Pymobiledevice3DocLink {
    /// README section on iOS 17+ tunnels (table and link to the guide).
    static let readmeSupportMatrix = URL(string: "https://github.com/doronz88/pymobiledevice3/blob/master/README.md#support-matrix-developer-services")!
    /// Guide with sample `RSD Address` / `RSD Port` output after `start-tunnel`.
    static let ios17TunnelsGuide = URL(string: "https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/ios17-tunnels.md#option-2-start-a-tunnel-manually")!
}

private enum DeveloperDiskImageDocLink {
    /// Community archive of Developer Disk Images when Xcode does not ship a folder for an exact iOS build.
    static let xcodeDeveloperDiskImagesReleases = URL(string: "https://github.com/mspvirajpatel/Xcode_Developer_Disk_Images/releases")!
}

struct DeveloperDiskImageHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Developer Disk Image (before iOS 17)")
                .font(.headline)

            Text(
                """
                Xcode bundles Developer Disk Images here:

                Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/<iOS version>/

                SimVirtualLocation builds paths from the Xcode path field above and your device’s iOS version (shown in the device list). Use Mount Developer Image after the device is connected and selected.

                If the exact version is missing (Mount fails or there is no folder for your build):

                • Install or update Xcode—new DeviceSupport folders often appear with each release.

                • Or download an image from the community archive (link below). If you need e.g. 16.5.1 but only 16.5 exists, duplicate that folder and rename it to match your exact version (e.g. 16.5.1), then put it under DeviceSupport next to the other version folders.
                """
            )
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            Link("Xcode Developer Disk Images (releases)", destination: DeveloperDiskImageDocLink.xcodeDeveloperDiskImagesReleases)
                .font(.subheadline)

            Spacer(minLength: 8)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 520)
    }
}

struct RSDHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RSD Address and Port")
                .font(.headline)

            Text(
                """
                Only needed when "No root required" is off.

                With that option on, SimVirtualLocation establishes the tunnel in-process using pymobiledevice3's userspace network stack—no Terminal, no sudo, and no address to copy. Just select your device above.

                Turn it off to use a kernel tunnel you started yourself, which is faster for large transfers. Run a command from the pymobiledevice3 documentation in Terminal—for example, on iOS 17.4+:

                sudo python3 -m pymobiledevice3 lockdown start-tunnel

                Or (including iOS 17.0–17.3.1):

                sudo python3 -m pymobiledevice3 remote start-tunnel

                The output will include "RSD Address" and "RSD Port" lines—copy them into the fields above. Keep the tunnel running while you mock location.
                """
            )
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Link("README: Support Matrix (Developer Services)", destination: Pymobiledevice3DocLink.readmeSupportMatrix)
                Link("More: iOS 17+ tunnels (RSD output example)", destination: Pymobiledevice3DocLink.ios17TunnelsGuide)
            }
            .font(.subheadline)

            Spacer(minLength: 8)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480)
    }
}

struct iOSDeviceSettings: View {
    @EnvironmentObject var locationController: LocationController
    @State private var showRSDHelp = false
    @State private var showDeveloperDiskHelp = false

    var body: some View {
        GroupBox {
            Picker("Device mode", selection: $locationController.deviceMode) {
                Text("Simulator").tag(DeviceMode.simulator)
                Text("Device").tag(DeviceMode.device)
            }.labelsHidden().pickerStyle(.segmented)

            if locationController.deviceMode == .simulator {
                Picker("Simulator:", selection: $locationController.selectedSimulator) {
                    ForEach(locationController.bootedSimulators, id: \.id) { simulator in
                        Text(simulator.name)
                    }
                }

                Button(action: {
                    Task {
                        await locationController.refreshDevices()
                    }
                }, label: {
                    Text("Refresh").frame(maxWidth: .infinity)
                })
            }

            if locationController.deviceMode == .device {
                Toggle(isOn: $locationController.useRSD) {
                    Text("iOS 17+")
                }
                if locationController.useRSD {
                    Picker("Connection", selection: $locationController.useUserspace) {
                        Text("Automatic").tag(true)
                        Text("Manual").tag(false)
                    }.labelsHidden().pickerStyle(.segmented)

                    if locationController.useUserspace {
                        Text("SimVirtualLocation connects to the device itself. No Terminal needed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // No Refresh button here: devices are rescanned automatically, and
                        // DeviceActivityView reports what is happening while none is found.
                        Picker("Device:", selection: $locationController.selectedDevice) {
                            ForEach(locationController.connectedDevices, id: \.id) { device in
                                Text("\(device.name) (\(device.version))")
                            }
                        }
                        .disabled(locationController.connectedDevices.isEmpty)

                        DeviceActivityView(activity: locationController.activity)
                    } else {
                        Text("Use a tunnel you started yourself. Requires Terminal and sudo.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("RSD Address", text: $locationController.rsdAddress)
                        TextField("RSD Port", text: $locationController.rsdPort)

                        Button(action: { showRSDHelp = true }, label: {
                            Label("Where to get RSD Address and Port", systemImage: "questionmark.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        })
                        .buttonStyle(.link)

                        DeviceActivityView(activity: locationController.activity)
                    }
                } else {
                    TextField("Xcode path", text: $locationController.xcodePath)
                    Picker("Device:", selection: $locationController.selectedDevice) {
                        ForEach(locationController.connectedDevices, id: \.id) { device in
                            Text("\(device.name) (\(device.version))")
                        }
                    }

                    Button(action: {
                        Task {
                            await locationController.refreshDevices()
                        }
                    }, label: {
                        Text("Refresh").frame(maxWidth: .infinity)
                    })

                    Button(action: {
                        locationController.mountDeveloperImage()
                    }, label: {
                        Text("Mount Developer Image").frame(maxWidth: .infinity)
                    })

                    Button(action: {
                        locationController.unmountDeveloperImage()
                    }, label: {
                        Text("Unmount Developer Image").frame(maxWidth: .infinity)
                    })

                    Button(action: { showDeveloperDiskHelp = true }, label: {
                        Label("Where to find the developer disk image (missing iOS version)", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    })
                    .buttonStyle(.link)
                }
            }
        }
        .sheet(isPresented: $showRSDHelp) {
            RSDHelpSheet()
        }
        .sheet(isPresented: $showDeveloperDiskHelp) {
            DeveloperDiskImageHelpSheet()
        }
    }
}

struct iOSDeviceSettings_Previews: PreviewProvider {
    static var previews: some View {
        iOSDeviceSettings()
            .environmentObject(LocationController(mapView: MapView()))
    }
}
