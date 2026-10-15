import SwiftUI
import WidgetKit
import MarketplaceFoundation

@main
struct DastakWidgets: WidgetBundle {
    var body: some Widget {
        DastakDailyWidget()
        DastakGroceryWidget()
        DastakFoodWidget()
        DastakSearchWidget()
        DastakOrderWidget()
        if #available(iOS 18.0, *) {
            DastakSearchControl()
            DastakGroceryControl()
            DastakFoodControl()
            DastakBasketControl()
            DastakTrackingControl()
        }
    }
}

@available(iOS 18.0, *)
@MainActor
private func dastakControlButton(_ target: DastakShortcutDestination) -> some ControlWidgetTemplate {
    let action = DastakAppAction(rawValue: target.rawValue)!
    return ControlWidgetButton(action: OpenDastakScreenIntent(target: target)) {
        Label(action.controlTitle, systemImage: action.controlSymbol)
            .controlWidgetActionHint(Text(action.controlActionHint))
    }
    .tint(Color(red: 0.91, green: 0.76, blue: 0.46))
}

@available(iOS 18.0, *)
struct DastakSearchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dastak.app.control.search") {
            dastakControlButton(.search)
        }.displayName("Search").description("Find groceries or food in Dastak.")
    }
}

@available(iOS 18.0, *)
struct DastakGroceryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dastak.app.control.grocery") {
            dastakControlButton(.grocery)
        }.displayName("Grocery").description("Browse everyday essentials in Dastak.")
    }
}

@available(iOS 18.0, *)
struct DastakFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dastak.app.control.food") {
            dastakControlButton(.food)
        }.displayName("Food").description("Explore nearby restaurants and cafés.")
    }
}

@available(iOS 18.0, *)
struct DastakBasketControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dastak.app.control.basket") {
            dastakControlButton(.basket)
        }.displayName("Basket").description("Review the items in your Dastak basket.")
    }
}

@available(iOS 18.0, *)
struct DastakTrackingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dastak.app.control.tracking") {
            dastakControlButton(.tracking)
        }.displayName("Track Order").description("Follow your delivery or view past orders.")
    }
}
