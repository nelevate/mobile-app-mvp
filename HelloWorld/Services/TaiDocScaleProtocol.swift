//
//  TaiDocScale.swift
//  HelloWorld
//
//  Created by Rafiq Whitley on 10/21/26.
//


//
//  TaiDocProtocol.swift
//  HelloWorld
//
//  Defines the Bluetooth Low Energy protocol candidates for the
//  TaiDoc TD-2555B.
//
//  NOTE: GATT UUIDs and payload format must be confirmed against
//  the actual device.
//

import Foundation
import CoreBluetooth

enum TaiDocScaleProtocol {

    // MARK: - Identity

    static let advertisedName = "TD-2555B"

    // MARK: - GATT UUIDs

    // Standard Bluetooth Weight Scale service (unconfirmed for TD-2555B).
    static let serviceUUID = CBUUID(string: "181D")

    // Standard Weight Measurement characteristic (unconfirmed).
    static let weightCharacteristicUUID = CBUUID(string: "2A9D")

    // MARK: - Value Parsing

    enum WeightUnit: Equatable {
        case kilograms
        case pounds
    }

    enum WeightMessage: Equatable {
        case measurement(weight: Double, unit: WeightUnit, bmi: Double?)
        case unknown(String)
    }

    /// Parses a standard Bluetooth Weight Measurement payload.
    ///
    /// Payload:
    /// - Byte 0: Flags
    /// - Bytes 1–2: Weight as IEEE-11073 SFLOAT, little-endian
    /// - Optional timestamp, user ID, and BMI/height fields follow.
    ///
    /// Flag bit 0: 0 = kg, 1 = lb
    /// Flag bit 1: timestamp present
    /// Flag bit 2: user ID present
    /// Flag bit 3: BMI and height present
    static func parse(_ data: Data) -> WeightMessage {
        let bytes = [UInt8](data)

        guard bytes.count >= 3 else {
            return .unknown("Invalid weight payload")
        }

        let flags = bytes[0]
        let unit: WeightUnit = flags & 0x01 == 0 ? .kilograms : .pounds

        let rawWeight = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)

        guard let weight = decodeSFloat(rawWeight) else {
            return .unknown("Invalid weight value")
        }

        var offset = 3

        // Skip the 7-byte date/time field when present.
        if flags & 0x02 != 0 {
            offset += 7
        }

        // Skip the 1-byte user ID when present.
        if flags & 0x04 != 0 {
            offset += 1
        }

        var bmi: Double?

        // BMI and height are both present when flag bit 3 is set.
        if flags & 0x08 != 0 {
            guard bytes.count >= offset + 4 else {
                return .unknown("Incomplete BMI/height payload")
            }

            let rawBMI = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)

            guard let decodedBMI = decodeSFloat(rawBMI) else {
                return .unknown("Invalid BMI value")
            }

            bmi = decodedBMI
        }

        return .measurement(weight: weight, unit: unit, bmi: bmi)
    }

    /// Decodes the IEEE-11073 16-bit SFLOAT format.
    private static func decodeSFloat(_ raw: UInt16) -> Double? {
        let mantissaBits = Int(raw & 0x0FFF)
        let exponentBits = Int((raw >> 12) & 0x000F)

        // Special values defined by IEEE-11073 SFLOAT.
        switch raw {
        case 0x07FE, 0x07FF, 0x0800, 0x0801, 0x0802:
            return nil
        default:
            break
        }

        let mantissa = mantissaBits >= 0x0800
            ? mantissaBits - 0x1000
            : mantissaBits

        let exponent = exponentBits >= 0x0008
            ? exponentBits - 0x0010
            : exponentBits

        return Double(mantissa) * pow(10.0, Double(exponent))
    }
}
