import Testing
@testable import GymLock

/// The Matrix port against the TypeScript golden values.
///
/// The goldens come from `docs/hero-pack/swift/tools/matrix-golden.ts`
/// run under bun against the web reference (hero13). Tolerances: hash 1e-11,
/// frame checksums 1e-9 relative, engine 1e-5. Each failure line names the
/// check and the got / want values.
@MainActor
struct MatrixParityTests {
    @Test func engineBoardAndScenesMatchTheWeb() {
        let failures = MatrixParity.run()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    /// Every generated scene (19 moments x 7 themes) at four contexts.
    @Test func allScenesMatchTheWeb() {
        let failures = MatrixParity.runAll()
        #expect(failures.isEmpty, "\(failures.prefix(40).joined(separator: "\n"))")
    }

    @Test func storyBoardMatchesTheWeb() {
        let failures = MatrixParity.runStory()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func cardKeepsItsAspect() {
        #expect(abs(MatrixCardGeometry.aspect - 1000.0 / 488.0) < 1e-12)
    }
}
