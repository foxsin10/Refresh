import SwiftUI

public enum RefreshState: Hashable {
    case idle, loading, pulling
}

public struct InterActionState: Hashable {
    public private(set) var state: RefreshState
    public private(set) var progress: CGFloat
    public private(set) var isCanceled: Bool = false

    public var isloading: Bool { state == .loading }
    public var ispulling: Bool { state == .pulling }
    public var idle: Bool { state == .idle }

    public init(state: RefreshState, progress: CGFloat) {
        self.state = state
        self.progress = progress
    }

    public mutating func updateProgress(_ progress: CGFloat) {
        self.progress = progress
    }

    public mutating func updateState(_ state: RefreshState) {
        self.state = state
        if state == .pulling {
            isCanceled = false
        }
    }

    public mutating func cancel() {
        self.isCanceled = true
    }
}
