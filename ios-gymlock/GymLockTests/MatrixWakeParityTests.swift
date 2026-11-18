#if DEBUG
import Testing
@testable import GymLock

/// The wake page's Matrix renderer against the web prototype's golden values
/// (tools/matrix-wake-golden.ts). Wired as the comment on `MatrixWakeParity` shows.
@MainActor
struct MatrixWakeParityTests {
    @Test func matrixWakeParity() { #expect(MatrixWakeParity.run() == []) }
}
#endif
