//
//  PulseRopeProtocolTests_swift.swift
//  PulseRopeProtocolTests.swift
//
//  Created by Rafiq Whitley on 10/21/26.
//

import Foundation
import Testing
@testable import HelloWorld

struct PulseRopeProtocolTests_swift {

    @Test
    func parsesStartingMessage() {
        let data = Data("Starting...".utf8)

        let result = PulseRopeProtocol.parse(data)

        #expect(result == .starting)
    }

}
