@testable import CurrentFeature

// This target is intentionally XCTest-free so `swift test` can compile on
// machines that only have Command Line Tools installed. The executable
// `CurrentFeatureChecks` runs the actual package validation scenarios.
func currentFeatureTestsCompile() {
    _ = StreamStore.defaultStreamName
}
