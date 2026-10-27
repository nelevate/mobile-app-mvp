//
//  BluetoothScannerTests.swift
//  BluetoothScannerTests
//
//  Created by Rafiq Whitley on 10/25/26.
//


import CoreBluetooth
import Testing
@testable import HelloWorld

struct BluetoothScannerTests {

    // MARK: - Scanning guards

    @Test
    func startScanWhenBluetoothIsPoweredOffDoesNotStartScanning() {
        let scanner = BluetoothScanner()
        scanner.bluetoothState = .poweredOff

        scanner.startScan()

        #expect(scanner.isScanning == false)
        #expect(scanner.statusMessage == "Cannot scan: Powered Off")
    }

    @Test
    func startScanWhenBluetoothStateIsUnknownDoesNotStartScanning() {
        let scanner = BluetoothScanner()
        scanner.bluetoothState = .unknown

        scanner.startScan()

        #expect(scanner.isScanning == false)
        #expect(scanner.statusMessage == "Cannot scan: Unknown")
    }

    @Test
    func startScanWhenBluetoothIsUnauthorizedDoesNotStartScanning() {
        let scanner = BluetoothScanner()
        scanner.bluetoothState = .unauthorized

        scanner.startScan()

        #expect(scanner.isScanning == false)
        #expect(scanner.statusMessage == "Cannot scan: Unauthorized")
    }

    // MARK: - Bluetooth state descriptions

    @Test
    func describesBluetoothStates() {
        #expect(
            BluetoothScanner.description(for: CBManagerState.poweredOn)
                == "Powered On"
        )

        #expect(
            BluetoothScanner.description(for: CBManagerState.poweredOff)
                == "Powered Off"
        )

        #expect(
            BluetoothScanner.description(for: CBManagerState.unauthorized)
                == "Unauthorized"
        )

        #expect(
            BluetoothScanner.description(for: CBManagerState.unsupported)
                == "Unsupported"
        )

        #expect(
            BluetoothScanner.description(for: CBManagerState.resetting)
                == "Resetting"
        )

        #expect(
            BluetoothScanner.description(for: CBManagerState.unknown)
                == "Unknown"
        )
    }

    // MARK: - Characteristic property descriptions

    @Test
    func describesReadAndNotifyProperties() {
        let properties: CBCharacteristicProperties = [.read, .notify]

        #expect(
            BluetoothScanner.description(for: properties) == "Read | Notify"
        )
    }

    @Test
    func describesNoCharacteristicProperties() {
        #expect(
            BluetoothScanner.description(for: []) == "None"
        )
    }
}
