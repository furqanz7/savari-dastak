import Foundation

/// Keep motion within a store; dissolve between independently authored interiors.
struct DastakEnvironmentTransition: Equatable {
    let duration: Double
    let dissolves: Bool
    init(from: DastakEnvironmentPlace?, to: DastakEnvironmentPlace, reducedMotion: Bool, active: Bool) {
        dissolves = from != nil && from?.isCafe != to.isCafe && !reducedMotion && active
        duration = from == nil || reducedMotion || !active ? 0 : dissolves ? 0.7 : 0.85
    }
    static func progress(_ fraction: Double) -> Double {
        let t = min(1, max(0, fraction))
        // Zero velocity and acceleration at both ends: no hard start or stop.
        return t*t*t*(t*(t*6-15)+10)
    }
    static func frameStep(_ elapsed: Double) -> Double {
        min(1.0/15,max(0,elapsed))
    }
}

/// Deterministic lifecycle budget shared by renderer and host regression tests.
struct DastakEnvironmentRenderPolicy: Equatable {
    let animates: Bool
    let framesPerSecond: Int
    init(active: Bool, reducedMotion: Bool, lowPower: Bool, thermalLimited: Bool) {
        animates = active && !reducedMotion
        framesPerSecond = thermalLimited ? 15 : lowPower ? 20 : 30
    }
}

public enum DastakEnvironmentPlace: String, Equatable, Sendable {
    case outside, grocery, groceryBilling, cafe, cafeCounter
    var isCafe: Bool { self == .cafe || self == .cafeCounter }

    static func customer(service: DastakCustomerService, cartPresented: Bool,
                         basketService: DastakBasketService? = nil) -> Self {
        if cartPresented, let basketService {
            return basketService == .food ? .cafeCounter : .groceryBilling
        }
        if service == .food { return cartPresented ? .cafeCounter : .cafe }
        return cartPresented ? .groceryBilling : .grocery
    }
}

struct DastakEnvironmentWeather: Hashable, Sendable {
    var daylight: Double
    var cloud: Double = 0
    var wind: Double = 3
    var precipitation: Double = 0
    var snow = false
    static func localClock(_ date: Date = Date(), calendar: Calendar = .current) -> Self {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        func smooth(_ v: Double) -> Double { let t = min(1, max(0, v)); return t*t*(3-2*t) }
        return .init(daylight: smooth((h-5.5)/1.25)*(1-smooth((h-17.5)/1.25)))
    }
}
