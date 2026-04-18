import SwiftUI
import WidgetKit

@main
struct MeerkatWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        MeerkatWidgetExtension()
        MeerkatWidgetCompact()
    }
}
