import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CricketFeed

// MARK: - Network stub

// Answers every URLSession.shared request in the tests, so nothing reaches ESPN.
// Routes by URL: a test registers a handler for a URL (or a matching rule) and
// anything with no handler fails with a "not connected" error.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [(match: @Sendable (URL) -> Bool, handler: Handler)] = []
    nonisolated(unsafe) private static var log: [URL] = []

    // Registers the stub for URLSession.shared once, before any test uses it.
    static let installed: Bool = {
        URLProtocol.registerClass(StubURLProtocol.self)
        return true
    }()

    static func reset() {
        _ = installed
        lock.withLock { routes = []; log = [] }
    }

    // Newest route wins, so a test can override an earlier one.
    static func on(_ match: @escaping @Sendable (URL) -> Bool, _ handler: @escaping Handler) {
        _ = installed
        lock.withLock { routes.insert((match, handler), at: 0) }
    }

    static func on(prefix: String, status: Int = 200, body: Data) {
        on({ $0.absoluteString.hasPrefix(prefix) }) { _ in (status, body) }
    }

    static func on(prefix: String, status: Int = 200, json: String) {
        on(prefix: prefix, status: status, body: Data(json.utf8))
    }

    static var requests: [URL] { lock.withLock { log } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let handler = Self.lock.withLock { () -> Handler? in
            Self.log.append(url)
            return Self.routes.first { $0.match(url) }?.handler
        }
        do {
            guard let handler else { throw URLError(.notConnectedToInternet) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// Every test that touches the network stub goes in a suite nested inside this one,
// so they run one at a time and never see each other's routes:
//
//     extension NetworkTests {
//         @Suite struct MyFetches { ... }
//     }
@Suite(.serialized) struct NetworkTests {}

// MARK: - Hosting views

// Puts a SwiftUI view in a window parked off screen, lays it out and lets SwiftUI
// settle, so `body` and its children actually run. The window is ordered front
// (off screen) because SwiftUI only takes clicks in a visible window.
@MainActor
@discardableResult
func host<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 600), settle: TimeInterval = 0.05) -> NSHostingView<V> {
    _ = NSApplication.shared
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    hosting.display()
    pump(settle)
    hosting.layoutSubtreeIfNeeded()
    retained.append(window)
    return hosting
}

// Clicks a point in the hosted view. `point` is in SwiftUI coordinates:
// x from the left, y down from the top of the view.
@MainActor
func click(_ hosting: NSView, at point: CGPoint, right: Bool = false, settle: TimeInterval = 0.05) {
    let window = hosting.window!
    let inWindow = hosting.convert(NSPoint(x: point.x, y: hosting.isFlipped ? point.y : hosting.bounds.height - point.y), to: nil)
    let types: [NSEvent.EventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
    for type in types {
        let e = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(e)
        pump(settle)
    }
}

// Moves the mouse over a point in the hosted view (SwiftUI coordinates), for hover effects.
@MainActor
func hover(_ hosting: NSView, at point: CGPoint, settle: TimeInterval = 0.05) {
    let window = hosting.window!
    window.acceptsMouseMovedEvents = true
    let inWindow = hosting.convert(NSPoint(x: point.x, y: hosting.isFlipped ? point.y : hosting.bounds.height - point.y), to: nil)
    let e = NSEvent.mouseEvent(with: .mouseMoved, location: inWindow, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    NSApp.sendEvent(e)
    pump(settle)
}

// Keeps hosting windows alive until the process ends, so late SwiftUI updates don't crash.
@MainActor private var retained: [NSWindow] = []

// Runs the main run loop briefly so async tasks and SwiftUI updates can finish.
@MainActor
func pump(_ seconds: TimeInterval = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
