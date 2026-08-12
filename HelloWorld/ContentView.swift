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
    // @State is the correct wrapper because BluetoothScanner is @Observable.
    @State private var scanner = BluetoothScanner()


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
                        Label("Scan for Devices", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scanner.bluetoothState != .poweredOn || scanner.isScanning)


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
        }
    }


    // MARK: - Subviews


    private var bluetoothStateSection: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 12, height: 12)
            Text("Bluetooth: \(BluetoothScanner.description(for: scanner.bluetoothState))")
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
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(scanner.isScanning
                         ? "Listening for advertisements…"
                         : "No devices yet. Press Scan to begin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(scanner.discoveredDevices) { device in
                    DeviceRow(device: device) {
                        // Tap behavior depends on current connection state.
                        switch device.connectionState {
                        case .disconnected, .failed:
                            scanner.connect(to: device)
                        case .connected, .ready:
                            scanner.disconnect(from: device)
                        case .connecting:
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
        case .poweredOn:  return .green
        case .poweredOff, .unauthorized, .unsupported: return .red
        case .resetting, .unknown: return .yellow
        @unknown default: return .gray
        }
    }
}


// MARK: - Row view


private struct DeviceRow: View {
    let device: DiscoveredPeripheral


    /// Called when the user taps anywhere on the row. The parent decides
    /// what tapping actually means (connect, disconnect, etc.) — this view
    /// stays presentational.
    let onTap: () -> Void


    var body: some View {
        // Button gives us free tap handling AND keyboard/accessibility
        // support without the fragility of .onTapGesture inside a List.
        // The .plain style prevents SwiftUI from tinting the label blue.
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(device.isLikelyPulseRope ? .green : .primary)
                    Spacer()
                    Text("RSSI: \(device.rssi)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }


                if device.isLikelyPulseRope {
                    Label("Likely Nelevate Pulse Rope", systemImage: "figure.jumprope")
                        .font(.caption)
                        .foregroundStyle(.green)
                }


                // Connection status line — always shown, so the visual
                // language of the row stays consistent whether or not
                // the user has interacted with it yet.
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)
                    Text(connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }


                // MARK: Live rep counter
                //
                // Only shown once the connection has reached .ready, i.e. we
                // have the characteristic in hand and notifications are
                // confirmed live. Before that, showing "Reps: 0" would be
                // misleading — the rope might have any count internally, we
                // just haven't heard from it yet.
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
            // Make the entire row area tappable, not just the text glyphs.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    // MARK: - Rep counter subview


    /// Big, glanceable rep number plus a small debug line showing the raw
    /// notification payload. The debug line is intentionally verbose during
    /// prototyping — it's the fastest way to distinguish "firmware isn't
    /// sending" from "we're mis-parsing what it sends".
    ///
    /// As of Task 4D there's a third line: the characteristic's advertised
    /// properties (e.g. "Read | Notify"). It's the smallest, dimmest line
    /// on purpose — it's an at-a-glance sanity check, not something the
    /// user needs to read every session. If it ever shows anything OTHER
    /// than "Read | Notify" for the rope, that's a firmware-contract change
    /// worth investigating.
    private var repCounterSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(device.repCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    // contentTransition animates the digit change instead
                    // of hard-swapping the label, which makes it much easier
                    // to spot each increment during testing.
                    .contentTransition(.numericText(value: Double(device.repCount)))
                    .animation(.snappy, value: device.repCount)
                Spacer()
            }

            // Raw last payload from the firmware. Fixed-height so the row
            // doesn't jitter when the string appears for the first time.
            Text(device.lastMessage ?? "Waiting for first notification…")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Characteristic properties diagnostic. Only shown when
            // populated (i.e. after characteristic discovery has actually
            // run). Kept in this section — rather than higher up in the
            // row — because it's only meaningful once we've got a live
            // subscription, which is exactly when this section is visible.
            if let properties = device.characteristicProperties {
                            Text("Props: \(properties)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        // Temporary diagnostic (Task 5A.2): shows whether we've seen
                        // the firmware's "Starting..." handshake, which is what tells
                        // us the counter is safe to trust. This line will be removed
                        // when WorkoutSession takes ownership of the "is the counter
                        // live" question and the row no longer needs to expose it.
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
        case .disconnected:   return .gray
        case .connecting:     return .yellow
        case .connected:      return .blue
        case .ready:          return .green
        case .failed:         return .red
        }
    }


    /// Human-readable label matching the dot color.
    ///
    /// Note: `.connected` now covers a slightly wider window than before —
    /// it spans from initial link-up through service/characteristic
    /// discovery and up until iOS confirms notifications are live. The
    /// status bar at the bottom of the screen carries the finer-grained
    /// story ("Discovering services…", "Subscribing…", etc.).
    private var connectionText: String {
        switch device.connectionState {
        case .disconnected:            return "Not connected — tap to connect"
        case .connecting:              return "Connecting…"
        case .connected:               return "Connected — preparing subscription…"
        case .ready:                   return "Ready — tap to disconnect"
        case .failed(let reason):      return "Failed: \(reason)"
        }
    }
}


#Preview {
    ContentView()
}
