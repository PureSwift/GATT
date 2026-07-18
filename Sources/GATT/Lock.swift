//
//  Lock.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/26.
//

#if canImport(Foundation)
import Foundation
#endif

/// Internal mutual exclusion primitive.
///
/// No-op on platforms without threading (e.g. Embedded Swift),
/// where the stack is driven by polling from the platform's run loop.
internal struct Lock: @unchecked Sendable {

    #if canImport(Foundation)
    private let nsLock = NSLock()
    #endif

    init() { }

    func lock() {
        #if canImport(Foundation)
        nsLock.lock()
        #endif
    }

    func unlock() {
        #if canImport(Foundation)
        nsLock.unlock()
        #endif
    }
}
