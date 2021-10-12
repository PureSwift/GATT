import XCTest

#if !canImport(Darwin)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(GATTTests.allTests),
    ]
}
#endif
