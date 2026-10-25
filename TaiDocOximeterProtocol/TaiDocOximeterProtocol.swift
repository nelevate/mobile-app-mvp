//
//  TaiDocOximeterProtocol.swift
//  TaiDocOximeterProtocol
//
//  Created by Rafiq Whitley on 10/21/26.
//

import Foundation
import Testing
@testable import HelloWorld

struct TaiDocOximeterProtocolTests {
    @Test
    func parsesSpO2AndPulseRate() {
        // SpO2: 98.0 = mantissa 980, exponent -1
        // Pulse: 72.0 = mantissa 720, exponent -1
        let data = Data([
            0x00,       // Flags
            0xD4, 0xF3, // SpO2: 98.0
            0xD0, 0xF2  // Pulse rate: 72.0
        ])

        let result = TaiDocOximeterProtocol.parse(data)

        #expect(result == .measurement(
            spo2: 98.0,
            pulseRate: 72.0
        ))
    }

    @Test
    func parsesSpO2WithoutPulseRate() {
        // The standard payload contains both fields.
        // An unavailable pulse rate is encoded as SFLOAT NaN (0x07FF).
        let data = Data([
            0x00,
            0xD4, 0xF3, // SpO2: 98.0
            0xFF, 0x07  // Pulse rate unavailable
        ])

        let result = TaiDocOximeterProtocol.parse(data)

        #expect(result == .measurement(
            spo2: 98.0,
            pulseRate: nil
        ))
    }

    @Test
    func parsesPulseRateWithoutSpO2() {
        let data = Data([
            0x00,
            0xFF, 0x07, // SpO2 unavailable
            0xD0, 0xF2  // Pulse rate: 72.0
        ])

        let result = TaiDocOximeterProtocol.parse(data)

        #expect(result == .measurement(
            spo2: nil,
            pulseRate: 72.0
        ))
    }

    @Test
    func returnsUnknownForPayloadTooShort() {
        let result = TaiDocOximeterProtocol.parse(
            Data([0x00, 0xD4, 0xF3, 0xD0])
        )

        #expect(result == .unknown("Invalid oximeter payload"))
    }

    @Test
    func returnsUnknownWhenBothMeasurementsAreUnavailable() {
        let data = Data([
            0x00,
            0xFF, 0x07, // SpO2 unavailable
            0xFF, 0x07  // Pulse rate unavailable
        ])

        let result = TaiDocOximeterProtocol.parse(data)

        #expect(result == .measurement(
            spo2: nil,
            pulseRate: nil
        ))
    }

    @Test
    func ignoresOptionalFieldsAfterMeasurements() {
        // Extra bytes represent optional fields not parsed here.
        let data = Data([
            0x00,
            0xD4, 0xF3, // SpO2: 98.0
            0xD0, 0xF2, // Pulse rate: 72.0
            0x01, 0x02, 0x03
        ])
        
        let result = TaiDocOximeterProtocol.parse(data)
        
        #expect(result == .measurement(
            spo2: 98.0,
            pulseRate: 72.0
        ))
    }
}
