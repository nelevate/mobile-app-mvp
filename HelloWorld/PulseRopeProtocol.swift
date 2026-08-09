//
//  PulseRopeProtocol.swift
//  HelloWorld
//
//  Defines the Bluetooth Low Energy protocol used by the Nelevate Pulse Rope
//  (firmware: FastRopeNoHR.ino, confirmed August 9, 2026).
//
//  This file is intentionally pure data + parsing. It has no dependencies on
//  UIKit, SwiftUI, or Core Bluetooth's runtime types beyond CBUUID. Keeping
//  protocol facts isolated here means the rest of the app never hard-codes
//  UUID strings, and if the firmware team changes the protocol we only have
//  to update this one file.
//

import Foundation
import CoreBluetooth

/// Namespace for everything related to the Pulse Rope BLE protocol.
///
/// We use a `caseless enum` (an enum with no cases) as a namespace rather
/// than a struct or class. This is a common Swift idiom: it prevents anyone
/// from accidentally instantiating it — you can't create a value of a type
/// that has no cases — while still letting us group related static members
/// under a single name like `PulseRopeProtocol.serviceUUID`.
enum PulseRopeProtocol {

    // MARK: - Identity

    /// The exact local name the rope advertises. Matched case-insensitively
    /// by the scanner. Confirmed from firmware line: `BLE.setLocalName("Nelevate Fast Rope")`.
    static let advertisedName = "Nelevate Fast Rope"

    // MARK: - GATT UUIDs

    /// The custom GATT service the rope exposes.
    ///
    /// Source: `BLEService IMUService("19B10000-E8F2-537E-4F6C-D104768A1214");`
    /// in FastRopeNoHR.ino. Despite the variable being named "IMUService" in
    /// firmware, this service currently carries rep-count data, not IMU data.
    /// The name is a firmware-side artifact from an earlier design.
    static let serviceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")

    /// The single characteristic within the service that reports rep counts.
    ///
    /// Source: `BLEStringCharacteristic switchCharacteristic("19B10001-...", BLERead | BLENotify, 20);`
    /// - Properties: Read + Notify
    /// - Max length: 20 bytes
    /// - Encoding: UTF-8 string
    static let repCharacteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")

    // MARK: - Value Parsing

    /// Represents a decoded message from the rep characteristic.
    ///
    /// The firmware sends two kinds of payloads:
    ///   • On connect, the initial value is the literal string "Starting..."
    ///   • On each completed rep, a string of the form ". Reps: <N>"
    ///
    /// We model these explicitly rather than just handing back a raw string,
    /// so callers can pattern-match on intent instead of doing ad-hoc parsing.
    enum RepMessage: Equatable {
        /// The rope just connected and sent its initial handshake value.
        case starting

        /// The rope reported a new rep count.
        case repCount(Int)

        /// The rope sent something we didn't recognize. We surface the raw
        /// string for logging so we can diagnose firmware changes rather
        /// than silently dropping the message.
        case unknown(String)
    }

    /// Parse a raw byte payload from the rep characteristic into a `RepMessage`.
    ///
    /// The firmware sends UTF-8 strings, but we defensively handle non-UTF-8
    /// data by returning `.unknown` with a placeholder rather than crashing.
    /// We also trim whitespace so we're tolerant of trailing newlines or
    /// nulls that some BLE stacks like to append.
    ///
    /// - Parameter data: The raw bytes received from the characteristic.
    /// - Returns: A structured interpretation of the payload.
    static func parse(_ data: Data) -> RepMessage {
        guard let raw = String(data: data, encoding: .utf8) else {
            return .unknown("<\(data.count) non-utf8 bytes>")
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Match the connect handshake exactly.
        if trimmed == "Starting..." {
            return .starting
        }

        // Match the rep format ". Reps: <N>". The firmware currently emits
        // a leading ". " which is almost certainly a bug, but we match it
        // as-is. We also accept the cleaner "Reps: <N>" form in case the
        // firmware is ever tidied up, so this parser doesn't break on a
        // well-intentioned cleanup by the firmware team.
        let candidates = [". Reps: ", "Reps: "]
        for prefix in candidates {
            if trimmed.hasPrefix(prefix) {
                let numberPart = trimmed.dropFirst(prefix.count)
                if let count = Int(numberPart) {
                    return .repCount(count)
                }
            }
        }

        return .unknown(trimmed)
    }
}
