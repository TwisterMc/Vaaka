import AppKit

// NOTE: Avoid declaring conformance of imported types to a protocol (e.g. Equatable)
// because the platform may introduce the conformance later, which can cause
// ambiguities. Provide a simple helper function instead.

@inlinable
public func NSEdgeInsetsEqual(_ lhs: NSEdgeInsets, _ rhs: NSEdgeInsets) -> Bool {
    return lhs.top == rhs.top && lhs.left == rhs.left && lhs.bottom == rhs.bottom && lhs.right == rhs.right
}
