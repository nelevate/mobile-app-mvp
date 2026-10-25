//
//  TaiDocBpProtocol.swift
//  HelloWorld
//
//  Created by Rafiq Whitley on 10/21/26.
//

import Foundation
import CoreBluetooth

enum TaiDocBpProtocol {

    // MARK: - Identity

    static let advertisedName = "TD-3128B"

    // MARK: - GATT UUIDs

    // Standard Bluetooth Blood Pressure Service.
    // Unconfirmed for the TD-3128B.
    static let serviceUUID = CBUUID(string: "1810")

    // Contains systolic, diastolic, and optional pulse rate.
    static let bloodPressureMeasurementCharacteristicUUID =
        CBUUID(string: "2A35")

    // MARK: - Value Parsing

    enum PressureUnit: Equatable {
        case mmHg
        case kPa
    }

    enum BloodPressureMessage: Equatable {
        case measurement(
            systolic: Double?,
            diastolic: Double?,
            heartRate: Double?,
            unit: PressureUnit
        )
        case unknown(String)
    }

    /// Parses a standard Bluetooth Blood Pressure Measurement payload.
    ///
    /// Byte 0: Flags
    /// Bytes 1–2: Systolic pressure (SFLOAT, little-endian)
    /// Bytes 3–4: Diastolic pressure (SFLOAT, little-endian)
    /// Bytes 5–6: Mean arterial pressure (SFLOAT, skipped)
    ///
    /// Optional fields follow in this order:
    /// Timestamp (7 bytes), pulse rate (2 bytes),
    /// user ID (1 byte), measurement status (2 bytes).
    static func parse(_ data: Data) -> BloodPressureMessage {
        let bytes = [UInt8](data)

        guard bytes.count >= 7 else {
            return .unknown("Invalid blood pressure payload")
        }

        let flags = bytes[0]
        let unit: PressureUnit = flags & 0x01 == 0 ? .mmHg : .kPa

        let rawSystolic = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        let rawDiastolic = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)

        let systolic = decodeSFloat(rawSystolic)
        let diastolic = decodeSFloat(rawDiastolic)

        // Skip systolic, diastolic, and mean arterial pressure.
        var offset = 7

        // Bit 1: Timestamp present.
        if flags & 0x02 != 0 {
            offset += 7
        }

        // Bit 2: Pulse rate present.
        var heartRate: Double?

        if flags & 0x04 != 0 {
            guard bytes.count >= offset + 2 else {
                return .unknown("Incomplete pulse rate payload")
            }

            let rawHeartRate =
                UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)

            heartRate = decodeSFloat(rawHeartRate)
            offset += 2
        }

        // Bit 3: User ID present.
        if flags & 0x08 != 0 {
            offset += 1
        }

        // Bit 4: Measurement status present.
        if flags & 0x10 != 0 {
            offset += 2
        }

        guard bytes.count >= offset else {
            return .unknown("Incomplete optional blood pressure fields")
        }

        return .measurement(
            systolic: systolic,
            diastolic: diastolic,
            heartRate: heartRate,
            unit: unit
        )
    }

    /// Decodes IEEE-11073 16-bit SFLOAT.
    /// Returns nil for special values, including unavailable data.
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
