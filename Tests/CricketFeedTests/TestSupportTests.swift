import SwiftUI
import Testing
@testable import CricketFeed

// Checks the click helper itself works, so view tests can rely on it.
extension UITests {
@MainActor @Suite struct TestSupportChecks {
    @Test func clickFiresButton() {
        final class Box { var n = 0 }
        let box = Box()
        let v = host(VStack(spacing: 0) {
            Button("Tap me") { box.n += 1 }.frame(width: 200, height: 40)
            Spacer()
        }.frame(width: 200, height: 200), size: CGSize(width: 200, height: 200))
        click(v, at: CGPoint(x: 100, y: 20))
        #expect(box.n == 1)
    }
}
}
