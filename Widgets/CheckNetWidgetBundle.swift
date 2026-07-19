import WidgetKit
import SwiftUI

@main
struct CheckNetWidgetBundle: WidgetBundle {
    var body: some Widget {
        LastPingWidget()
        PingLiveActivityWidget()
    }
}
