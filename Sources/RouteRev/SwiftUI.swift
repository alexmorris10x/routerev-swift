#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Records one screen event each time this view appears. Returning to the screen
    /// records another appearance; ordinary body updates do not send an event.
    @MainActor public func routeRevScreen(_ name: String, _ props: [String: RouteRevValue] = [:]) -> some View {
        onAppear { RouteRev.screen(name, props) }
    }
}
#endif
