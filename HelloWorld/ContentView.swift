//
//  ContentView.swift
//  HelloWorld
//
//  Debug UI for Milestone 4A — Core Bluetooth scanning.
//


//
//  ContentView.swift
//  HelloWorld
//
//  Debug UI for Milestone 4A — Core Bluetooth scanning.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {

    // A single scanner instance owned by this view's lifetime.
    @State private var scanner = BluetoothScanner()

    /// ID of the peripheral whose workout screen is currently pushed.
    @State private var openWorkoutForID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                // MARK: Bluetooth state
                bluetoothStateSection

                // MARK: Scan controls
                HStack(spacing: 12) {
                    Button {
                        scanner.startScan()
                    } label: {
                        Label(
                            "Scan for Devices",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        scanner.bluetoothState != .poweredOn ||
                        scanner.isScanning
                    )

                    Button {
                        scanner.stopScan()
                    } label: {
                        Label("Stop Scan", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!scanner.isScanning)
                }
                .padding(.horizontal)

                // MARK: Section header
                HStack {
                    Text("Nearby Devices")
                        .font(.headline)

                    Spacer()

                    Text("\(scanner.discoveredDevices.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // MARK: Device list
                deviceListSection

                // MARK: Status bar
                statusSection
            }
            .padding(.vertical)
            .navigationTitle("Nelevate BLE Prototype")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $openWorkoutForID) { id in
                if let device = scanner.discoveredDevices.first(where: {
                    $0.id == id
                }) {
                    WorkoutContainerView(peripheral: device)
                        .id(id)
                }
            }
        }
    }

    // MARK: - Subviews

    private var bluetoothStateSection: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 12, height: 12)

            Text(
                "Bluetooth: \(BluetoothScanner.description(for: scanner.bluetoothState))"
            )
            .font(.subheadline)
            .fontWeight(.medium)

            Spacer()
        }
        .padding(.horizontal)
    }

    private var deviceListSection: some View {
        Group {
            if scanner.discoveredDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(
                        systemName: "antenna.radiowaves.left.and.right.slash"
                    )
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                    Text(
                        scanner.isScanning
                            ? "Listening for advertisements…"
                            : "No devices yet. Press Scan to begin."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(scanner.discoveredDevices) { device in
                    DeviceRow(device: device) {
                        // Tapping connects disconnected devices or opens
                        // the workout screen for ready devices.
                        switch device.connectionState {
                        case .disconnected, .failed:
                            scanner.connect(to: device)

                        case .ready:
                            openWorkoutForID = device.id

                        case .connecting, .connected:
                            break
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(scanner.statusMessage)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Helpers

    /// Traffic-light color for the Bluetooth state dot.
    private var stateColor: Color {
        switch scanner.bluetoothState {
        case .poweredOn:
            return .green
        case .poweredOff, .unauthorized, .unsupported:
            return .red
        case .resetting, .unknown:
            return .yellow
        @unknown default:
            return .gray
        }
    }
}

// MARK: - Row view

private struct DeviceRow: View {
    let device: DiscoveredPeripheral

    /// The parent decides what tapping the row does.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(
                            device.isLikelyPulseRope ? .green : .primary
                        )

                    Spacer()

                    Text("RSSI: \(device.rssi)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if device.isLikelyPulseRope {
                    Label(
                        "Likely Nelevate Pulse Rope",
                        systemImage: "figure.jumprope"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                }

                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)

                    Text(connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Battery level
                if showsBattery {
                    batterySection
                }

                // MARK: Live rep counter
                if case .ready = device.connectionState {
                    repCounterSection
                }

                Text("Identifier: \(device.id.uuidString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Battery

    /// Show battery information only while connected.
    private var showsBattery: Bool {
        switch device.connectionState {
        case .connected, .ready:
            return true
        case .disconnected, .connecting, .failed:
            return false
        }
    }

    private var batterySection: some View {
        HStack(spacing: 5) {
            Image(systemName: batterySymbol)
                .foregroundStyle(batteryColor)

            if let level = device.batteryLevel {
                Text("Battery: \(level)%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Battery unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var batterySymbol: String {
        guard let level = device.batteryLevel else {
            return "battery.0percent"
        }

        switch level {
        case 0..<20:
            return "battery.25percent"
        case 20..<50:
            return "battery.50percent"
        case 50..<75:
            return "battery.75percent"
        default:
            return "battery.100percent"
        }
    }

    private var batteryColor: Color {
        guard let level = device.batteryLevel else {
            return .secondary
        }

        if level <= 20 {
            return .red
        }

        if level <= 50 {
            return .orange
        }

        return .green
    }

    // MARK: - Rep counter

    private var repCounterSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("\(device.repCount)")
                    .font(
                        .system(
                            size: 44,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .contentTransition(
                        .numericText(value: Double(device.repCount))
                    )
                    .animation(.snappy, value: device.repCount)

                Spacer()
            }

            // Raw notification payload
            Text(
                device.lastMessage ?? "Waiting for first notification…"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)

            // Characteristic properties diagnostic
            if let properties = device.characteristicProperties {
                Text("Props: \(properties)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Counter validation diagnostic
            if device.hasValidatedCumulativeCount {
                Text("Counter validated ✓")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.green)
            } else {
                Text("Counter not yet validated…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Connection state presentation

    /// Traffic-light color for the connection status dot.
    private var connectionColor: Color {
        switch device.connectionState {
        case .disconnected:
            return .gray
        case .connecting:
            return .yellow
        case .connected:
            return .blue
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }

    /// Human-readable connection state.
    private var connectionText: String {
        switch device.connectionState {
        case .disconnected:
            return "Not connected — tap to connect"
        case .connecting:
            return "Connecting…"
        case .connected:
            return "Connected — preparing subscription…"
        case .ready:
            return "Ready — tap to start workout"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}

#Preview {
    ContentView()
}

