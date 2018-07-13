import XCTest
import GATTTests

var tests = [XCTestCaseEntry]()
tests += GATTTests.allTests()
XCTMain(tests)
