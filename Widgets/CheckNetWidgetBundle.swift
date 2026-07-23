import WidgetKit
import SwiftUI

/// The extension ships the Live Activity plus user-added controls (Control
/// Center / Lock Screen). Still nothing in the Home Screen widget gallery — no
/// widget appears until the user deliberately adds a control.
@main
struct CheckNetWidgetBundle: WidgetBundle {
    var body: some Widget {
        CheckLiveActivityWidget()
        PingControl()
        BlockingControl()
    }
}
