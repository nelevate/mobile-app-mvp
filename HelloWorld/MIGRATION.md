# BLE View Refactor — Migration Guide

## What Changed

| Issue | Before | After |
|-------|--------|-------|
| State ownership | `@State private var scanner = BluetoothScanner()` in `ContentView` | `BluetoothManager` injected via `.environment()` from `HelloWorldApp` |
| Business logic in view | `switch device.connectionState { ... }` inside `DeviceRow` closure | `scanner.handleDeviceTap(device)` protocol method |
| Monolithic view | `ContentView` ~300 lines with 3 embedded sections | `ContentView` ~60 lines; extracted `BluetoothStatusHeader`, `ScanControlBar`, `DeviceList`, `StatusFooter` |
| Bloated row | `DeviceRow` had battery, rep counter, diagnostics | `DeviceRow` shows identity + connection only; `BatteryIndicator`, `RepCounterView`, `DeviceDiagnosticsView` are separate |
| Broken previews | `#Preview { ContentView() }` triggers real Bluetooth | Previews use `MockBluetoothCentralAdapter`; canvas works without hardware |
| Fragile navigation | `openWorkoutForID: UUID?` + lookup in `discoveredDevices` | `selectedDevice: DiscoveredPeripheral?` stable independent of scan list |

## Files to Add

1. `BluetoothScanning.swift` — protocol
2. `BluetoothManager+BluetoothScanning.swift` — extension adding `handleDeviceTap`
3. `BluetoothStatusHeader.swift`
4. `ScanControlBar.swift`
5. `DeviceList.swift`
6. `StatusFooter.swift`
7. `BatteryIndicator.swift`
8. `RepCounterView.swift`
9. `DeviceDiagnosticsView.swift`
10. `MockBluetoothCentralAdapter.swift` — preview helper

## Files to Modify

1. `HelloWorldApp.swift`
   ```swift
   private let scanner = BluetoothManager()
   // ...
   ContentView().environment(scanner)
   ```

2. `ContentView.swift` — replace entirely with the refactored version

3. `DeviceRow.swift` — replace entirely with the refactored version

4. `BluetoothManager.swift` — no changes required if you add the `BluetoothManager+BluetoothScanning.swift` file. If you prefer, paste the extension directly into `BluetoothManager.swift` and skip the separate file.

## Files to Delete

None. The old `ContentView` and `DeviceRow` are overwritten.

## Adoption Steps

1. Copy all new files into `HelloWorld/`
2. Replace `HelloWorldApp.swift`, `ContentView.swift`, `DeviceRow.swift` with the refactored versions
3. Build → fix any import issues (should be none)
4. Open Canvas → verify previews render without Bluetooth permission dialogs

## If You Want the Battery / Rep Counter Back in the Row

The refactored `DeviceRow` is intentionally thin. If you want the full dashboard row back:

```swift
// In DeviceList.swift, inside the list row:
DeviceRow(device: device, onTap: { ... })

if case .ready = device.connectionState {
    RepCounterView(count: device.repCount, lastMessage: device.lastMessage)
}
```

Or compose them in a new `DeviceDashboardRow` that wraps `DeviceRow` + `BatteryIndicator` + `RepCounterView` + `DeviceDiagnosticsView`.

## Testing

- Previews now work without hardware
- You can write unit tests against `MockBluetoothScanner` (or create your own mock conforming to `BluetoothScanning`)
- `BluetoothManager` itself is still testable via its `centralManagerFactory` injection
