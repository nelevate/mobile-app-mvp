//
//  DiscoveredPeripheral.swift
//  HelloWorld
//
//  A single BLE device row: identity, live signal strength, connection
//  state, and (once connected) the characteristic we listen to for rep data.
//

import Foundation
import CoreBluetooth
import Observation


/// One discovered BLE device, as seen by BluetoothScanner.
///
/// This is a reference type (`class`) rather than a struct for two reasons:
///   1. `CBPeripheral` is itself a reference type, and it's the identity
///      anchor for everything else — modeling the row as a struct would
///      mean copying peripheral references around and getting confused
///      about which copy is "the" entry.
///   2. `@Observable` on a class lets SwiftUI observe individual property
///      changes (e.g. rssi ticking, connectionState flipping) without
///      needing to replace the whole entry in the parent array.
@Observable
final class DiscoveredPeripheral: Identifiable {


    // MARK: - Connection state
    //
    // Mirrors the lifecycle of a Core Bluetooth connection, plus a terminal
    // `.ready` state that means "GATT discovery is done, we have the
    // characteristic in hand, and notifications are confirmed live by iOS."
    // (Task 4D tightened this definition — previously `.ready` was set as
    // soon as the characteristic was found, before notifications were
    // actually confirmed enabled.)
    // We keep `.failed` separate from `.disconnected` so the UI can show a
    // reason string when appropriate.
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected           // link up, but services not yet discovered
        case ready               // link up AND notifications confirmed live
        case failed(String)      // reason for display in the UI
    }


    // MARK: - Identity


    /// Stable identifier — matches `peripheral.identifier`. Used both by
    /// SwiftUI (`Identifiable`) and by BluetoothScanner to dedupe entries.
    var id: UUID { peripheral.identifier }


    /// The underlying Core Bluetooth handle. Held strongly because iOS
    /// will not deliver delegate callbacks for a peripheral we don't
    /// retain — one of the most common Core Bluetooth footguns.
    let peripheral: CBPeripheral


    // MARK: - Advertised / observed data


    /// Best name we've seen so far for this device. May be nil if the
    /// device never advertises a local name; `displayName` handles that.
    var name: String?


    /// Most recent RSSI (signal strength in dBm). More negative = weaker.
    var rssi: Int


    /// Timestamp of the most recent advertisement we heard from this
    /// device. Useful for surfacing stale entries in a future milestone.
    var lastSeen: Date


    // MARK: - Connection / GATT state


    /// Where this device sits in the connect → discover → ready pipeline.
    /// SwiftUI observes this to color status dots, enable buttons, etc.
    var connectionState: ConnectionState = .disconnected


    /// The characteristic used for rep-count notifications, populated during
    /// service discovery (Task 4). Stored on the entry — rather than in a
    /// separate dictionary on the scanner — so Task 5's notification handling
    /// has direct access to it without a lookup indirection.
    var repCharacteristic: CBCharacteristic?


    /// Human-readable description of the rep characteristic's properties
    /// (e.g. "Read | Notify"), captured at discovery time.
    ///
    /// Populated by `BluetoothScanner` in `didDiscoverCharacteristicsFor`
    /// and cleared on disconnect. Displayed in the device row purely as a
    /// diagnostic — it lets a developer verify at a glance that the
    /// firmware is exposing the capabilities we expect. If a future
    /// firmware revision silently drops Notify (or adds Write), this
    /// string is where we'd first see it.
    ///
    /// Optional because until characteristic discovery completes we have
    /// nothing to show. Nil is meaningfully different from an empty string
    /// (which would incorrectly imply "characteristic has no properties").
    ///
    /// Note: this property is added in Task 4D. Until `BluetoothScanner`
    /// is updated to populate it (Step 4D.2), it will always remain nil —
    /// which is harmless; the UI just won't display anything for it yet.
    var characteristicProperties: String?


    // MARK: - Rope-specific runtime data
    //
    // These are populated in Task 5 when we start receiving notifications.
    // They live here (rather than on a separate model) so a single row in
    // the UI has everything it needs to render — name, RSSI, connection
    // status, and the latest rep telemetry — in one observed object.


    /// Running count of reps reported by the rope. Reset to 0 on disconnect
    /// so a reconnect starts clean and matches the firmware's own counter,
    /// which also resets on connect.
    var repCount: Int = 0
    
    /// Whether we've seen definitive evidence that `repCount` is trustworthy
    /// as a fresh baseline for this connection.
    ///
    /// The firmware contract is that on every connect, the rope's first
    /// characteristic notification is the literal string "Starting...". When
    /// we see that, we know: (a) the rope's counter is 0, and (b) any
    /// subsequent "Reps: N" values are cumulative from this moment.
    ///
    /// This flag exists because WorkoutSession (upcoming) will need to know
    /// when the raw counter is safe to trust. Before it's true, `repCount`
    /// might reflect a stale value from a previous connection or a race
    /// between subscribe and the first firmware write. After it's true, the
    /// counter can be treated as authoritative for the current session.
    ///
    /// Reset to false on disconnect so a subsequent reconnect re-validates.
    var hasValidatedCumulativeCount: Bool = false


    /// The most recent raw message string received from the rope, kept
    /// primarily for debugging in Task 5. Cleared on disconnect.
    var lastMessage: String?


    // MARK: - Derived


    /// Name to show in the UI. Falls back to a friendly placeholder when
    /// the peripheral hasn't advertised a local name — some devices only
    /// send a name in their scan response, which iOS may not deliver until
    /// after the first advertisement callback.
    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return "Unnamed device"
    }


    /// Best-effort heuristic for "does this look like the Nelevate rope?"
    ///
    /// Used purely for UI hinting — for example, surfacing a badge or
    /// pushing likely ropes to the top of the list — NOT for gating any
    /// real behavior. The authoritative check is service-UUID discovery
    /// after connect (see `BluetoothScanner`'s CBPeripheralDelegate
    /// extension), which is the only way to be sure. We match loosely
    /// on name so cosmetic firmware relabels ("Nelevate FastRope",
    /// "NelevateRope v2", etc.) still light up the hint.
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


    // MARK: - Init


    /// Create a new entry from a fresh discovery callback.
    ///
    /// The initializer seeds `name` from `peripheral.name` because that's
    /// the only source available synchronously; the scanner overwrites it
    /// immediately afterward if the advertisement packet carried a better
    /// (or any) name via `CBAdvertisementDataLocalNameKey`.
    init(peripheral: CBPeripheral, rssi: Int) {
        self.peripheral = peripheral
        self.name = peripheral.name
        self.rssi = rssi
        self.lastSeen = Date()
    }
}
