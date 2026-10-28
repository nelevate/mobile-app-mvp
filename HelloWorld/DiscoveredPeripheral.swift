//
//  DiscoveredPeripheral.swift
//  HelloWorld
//
//  A single BLE device row: identity, live signal strength, connection
//  state, and (once connected) the characteristic we listen to for rep data.
//
import CoreBluetooth
import Foundation
import Observation

@Observable
final class DiscoveredPeripheral: Identifiable, Hashable {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case ready
        case failed(String)
    }

    var id: UUID { peripheral.identifier }

    let peripheral: any BluetoothPeripheralManaging

    var name: String?
    var batteryLevel: Int?
    var rssi: Int
    var lastSeen = Date()
    var connectionState: ConnectionState = .disconnected
    var repCharacteristic: BluetoothCharacteristic?
    var characteristicProperties: String?
    var repCount = 0
    var hasValidatedCumulativeCount = false
    var lastMessage: String?

    var displayName: String {
        guard let name, !name.isEmpty else {
            return "Unnamed device"
        }
        return name
    }

    var isLikelyPulseRope: Bool {
        guard let name = name?.lowercased(), !name.isEmpty else {
            return false
        }

        return name.contains("nelevate")
            || name.contains("fast rope")
            || name.contains("fastrope")
            || name.contains("pulse rope")
            || name.contains("pulserope")
    }

    init(
        peripheral: any BluetoothPeripheralManaging,
        rssi: Int
    ) {
        self.peripheral = peripheral
        self.name = peripheral.name
        self.rssi = rssi
    }

    // MARK: - Hashable

    static func == (lhs: DiscoveredPeripheral, rhs: DiscoveredPeripheral) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

