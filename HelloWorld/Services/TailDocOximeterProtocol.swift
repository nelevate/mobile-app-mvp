//
//  TailDocOximeter.swift
//  HelloWorld
//
//  Created by Rafiq Whitley on 10/21/26.
//

import Foundation
import CoreBluetooth

enum TaiDocOximeterProtocol {

    // MARK: - Identity

    static let advertisedName = "TD-8255B"

    // MARK: - GATT UUIDs

    // Standard Bluetooth Pulse Oximeter service.
    // Unconfirmed for the TD-8255B.
    static let serviceUUID = CBUUID(string: "1822")

    // Standard PLX measurement characteristics.
    static let spotCheckSpO2PulseRateCharacteristicUUID = CBUUID(string: "2A5E")
    static let continuousSpO2PulseRateCharacteristicUUID = CBUUID(string: "2A5F")

    // MARK: - Value Parsing

    enum OximeterMessage: Equatable {
        case measurement(spo2: Double?, pulseRate: Double?)
        case unknown(String)
    }

    /// Parses the core fields of a standard Bluetooth PLX measurement.
    ///
    /// - Byte 0: Flags
    /// - Bytes 1–2: SpO2 as IEEE-11073 SFLOAT, little-endian
    /// - Bytes 3–4: Pulse rate as IEEE-11073 SFLOAT, little-endian
    /// - Remaining optional fields are ignored.
    static func parse(_ data: Data) -> OximeterMessage {
        let bytes = [UInt8](data)

        guard bytes.count >= 5 else {
            return .unknown("Invalid oximeter payload")
        }

        let rawSpO2 = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        let rawPulseRate = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)

        let spo2 = decodeSFloat(rawSpO2)
        let pulseRate = decodeSFloat(rawPulseRate)

        return .measurement(
            spo2: spo2,
            pulseRate: pulseRate
        )
    }

    /// Decodes IEEE-11073 16-bit SFLOAT.
    /// Returns nil for special values representing unavailable data.
    private static func decodeSFloat(_ raw: UInt16) -> Double? {
        switch raw {
        case 0x07FE, 0x07FF, 0x0800, 0x0801, 0x0802:
            return nil
        default:
            break
        }

        let mantissaBits = Int(raw & 0x0FFF)
        let exponentBits = Int((raw >> 12) & 0x000F)

        let mantissa = mantissaBits >= 0x0800
            ? mantissaBits - 0x1000
            : mantissaBits

        let exponent = exponentBits >= 0x0008
            ? exponentBits - 0x0010
            : exponentBits

        return Double(mantissa) * pow(10.0, Double(exponent))
    }
}
