import WidgetKit
import SwiftUI

/// The extension ships only the Live Activity: nothing is published to the
/// widget gallery, so no widget shows up after installing the app.
@main
struct CheckNetWidgetBundle: WidgetBundle {
    var body: some Widget {
        PingLiveActivityWidget()
    }
}
