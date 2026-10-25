//
//  TaiDocBpProtocol.swift
//  TaiDocBpProtocol
//
//  Created by Rafiq Whitley on 10/21/26.
//

import Foundation
import Testing
@testable import HelloWorld

struct TaiDocBpProtocolTests {

    @Test
    func parsesSystolicDiastolicAndHeartRate() {
        // Systolic: 120.0
        // Diastolic: 80.0
        // Mean arterial pressure: 93.0 (ignored)
        // Heart rate: 72.0
        let data = Data([
            0x04,       // Pulse rate present; unit is mmHg
            0xB0, 0xF4, // Systolic: 120.0
            0x20, 0xF3, // Diastolic: 80.0
            0xA2, 0xF3, // Mean arterial pressure: 93.0
            0xD0, 0xF2  // Heart rate: 72.0
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .measurement(
            systolic: 120.0,
            diastolic: 80.0,
            heartRate: 72.0,
            unit: .mmHg
        ))
    }

    @Test
    func parsesBloodPressureWithoutHeartRate() {
        let data = Data([
            0x00,       // No optional fields; unit is mmHg
            0xB0, 0xF4, // Systolic: 120.0
            0x20, 0xF3, // Diastolic: 80.0
            0xA2, 0xF3  // Mean arterial pressure: 93.0
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .measurement(
            systolic: 120.0,
            diastolic: 80.0,
            heartRate: nil,
            unit: .mmHg
        ))
    }

    @Test
    func parsesKPaUnit() {
        let data = Data([
            0x01,       // Unit is kPa
            0xB0, 0xF4, // Systolic: 120.0
            0x20, 0xF3, // Diastolic: 80.0
            0xA2, 0xF3  // Mean arterial pressure: 93.0
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .measurement(
            systolic: 120.0,
            diastolic: 80.0,
            heartRate: nil,
            unit: .kPa
        ))
    }

    @Test
    func skipsTimestampBeforeHeartRate() {
        let data = Data([
            0x06,       // Timestamp and pulse rate present
            0xB0, 0xF4, // Systolic: 120.0
            0x20, 0xF3, // Diastolic: 80.0
            0xA2, 0xF3, // Mean arterial pressure: 93.0
            // Timestamp: year, month, day, hour, minute, second
            0xEA, 0x07, // Year: 2026
            0x0A,       // Month: October
            0x14,       // Day: 20
            0x0C,       // Hour: 12
            0x1E,       // Minute: 30
            0x00,       // Second: 0
            0xD0, 0xF2  // Heart rate: 72.0
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .measurement(
            systolic: 120.0,
            diastolic: 80.0,
            heartRate: 72.0,
            unit: .mmHg
        ))
    }

    @Test
    func skipsUserIDAndMeasurementStatus() {
        let data = Data([
            0x1C,       // Pulse rate, user ID, and status present
            0xB0, 0xF4, // Systolic: 120.0
            0x20, 0xF3, // Diastolic: 80.0
            0xA2, 0xF3, // Mean arterial pressure: 93.0
            0xD0, 0xF2, // Heart rate: 72.0
            0x01,       // User ID
            0x00, 0x00  // Measurement status
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .measurement(
            systolic: 120.0,
            diastolic: 80.0,
            heartRate: 72.0,
            unit: .mmHg
        ))
    }

    @Test
    func returnsNilForUnavailableHeartRate() {
        let data = Data([
            0x04,
            0xB0, 0xF4, // Systolic: 120.0
            0x20, 0xF3, // Diastolic: 80.0
            0xA2, 0xF3, // Mean arterial pressure: 93.0
            0xFF, 0x07  // Heart rate unavailable (SFLOAT NaN)
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .measurement(
            systolic: 120.0,
            diastolic: 80.0,
            heartRate: nil,
            unit: .mmHg
        ))
    }

    @Test
    func returnsUnknownForPayloadTooShort() {
        let result = TaiDocBpProtocol.parse(
            Data([0x04, 0xB0, 0xF4, 0x20, 0xF3])
        )

        #expect(result == .unknown("Invalid blood pressure payload"))
    }

    @Test
    func returnsUnknownForIncompleteHeartRate() {
        let data = Data([
            0x04,
            0xB0, 0xF4,
            0x20, 0xF3,
            0xA2, 0xF3,
            0xD0 // Only one of the two heart-rate bytes
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .unknown("Incomplete pulse rate payload"))
    }

    @Test
    func returnsUnknownForIncompleteTimestampAndHeartRate() {
        let data = Data([
            0x06,       // Timestamp and pulse rate present
            0xB0, 0xF4,
            0x20, 0xF3,
            0xA2, 0xF3,
            0xEA, 0x07  // Incomplete timestamp
        ])

        let result = TaiDocBpProtocol.parse(data)

        #expect(result == .unknown("Incomplete pulse rate payload"))
    }
}
