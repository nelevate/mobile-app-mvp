//
//  TaiDocScaleProtocol.swift
//  TaiDocScaleProtocol
//
//  Created by Rafiq Whitley on 10/21/26.
//

import Foundation
import Testing
@testable import HelloWorld

struct TaiDocScaleProtocolTests {

    @Test
    func parsesKilogramWeightWithoutBMI() {
        // SFLOAT: 700 × 10⁻¹ = 70.0 kg
        let data = Data([0x00, 0xBC, 0xF2])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .measurement(
            weight: 70.0,
            unit: .kilograms,
            bmi: nil
        ))
    }

    @Test
    func parsesPoundWeightWithoutBMI() {
        // SFLOAT: 1600 × 10⁻¹ = 160.0 lb
        let data = Data([0x01, 0x40, 0xF6])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .measurement(
            weight: 160.0,
            unit: .pounds,
            bmi: nil
        ))
    }

    @Test
    func parsesWeightAndBMI() {
        // Flags: kg + BMI/height present.
        // Weight: 700 × 10⁻¹ = 70.0 kg
        // BMI: 225 × 10⁻¹ = 22.5
        let data = Data([
            0x08,
            0xBC, 0xF2, // Weight: 70.0
            0xE1, 0xF0, // BMI: 22.5
            0xB0, 0x0B  // Height
        ])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .measurement(
            weight: 70.0,
            unit: .kilograms,
            bmi: 22.5
        ))
    }

    @Test
    func skipsTimestampBeforeBMI() {
        // Flags: kg + timestamp + BMI/height.
        let data = Data([
            0x0A,
            0xBC, 0xF2, // Weight: 70.0
            0xEA, 0x07, 0x0A, 0x15, 0x0C, 0x00, 0x00, // Timestamp
            0xE1, 0xF0, // BMI: 22.5
            0xB0, 0x0B  // Height
        ])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .measurement(
            weight: 70.0,
            unit: .kilograms,
            bmi: 22.5
        ))
    }

    @Test
    func skipsUserIDBeforeBMI() {
        // Flags: kg + user ID + BMI/height.
        let data = Data([
            0x0C,
            0xBC, 0xF2, // Weight: 70.0
            0x01,       // User ID
            0xE1, 0xF0, // BMI: 22.5
            0xB0, 0x0B  // Height
        ])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .measurement(
            weight: 70.0,
            unit: .kilograms,
            bmi: 22.5
        ))
    }

    @Test
    func returnsUnknownForPayloadTooShort() {
        let result = TaiDocScaleProtocol.parse(
            Data([0x00, 0xBC])
        )

        #expect(result == .unknown("Invalid weight payload"))
    }

    @Test
    func returnsUnknownForInvalidWeightSFloat() {
        // 0x07FE is a reserved SFLOAT value.
        let data = Data([0x00, 0xFE, 0x07])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .unknown("Invalid weight value"))
    }

    @Test
    func returnsUnknownForIncompleteBMIAndHeight() {
        // BMI/height flag set, but only BMI bytes are provided.
        let data = Data([
            0x08,
            0xBC, 0xF2, // Weight: 70.0
            0xE1, 0xF0  // BMI: 22.5; height is missing
        ])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .unknown("Incomplete BMI/height payload"))
    }

    @Test
    func returnsUnknownForInvalidBMISFloat() {
        let data = Data([
            0x08,
            0xBC, 0xF2, // Weight: 70.0
            0xFE, 0x07, // Invalid BMI SFLOAT
            0xB0, 0x0B  // Height
        ])

        let result = TaiDocScaleProtocol.parse(data)

        #expect(result == .unknown("Invalid BMI value"))
    }
}
