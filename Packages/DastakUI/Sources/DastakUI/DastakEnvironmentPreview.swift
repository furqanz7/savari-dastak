#if DEBUG
import SwiftUI

/// Development-only camera/weather review. No authentication or commerce transport.
public struct DastakEnvironmentPreview: View {
    @State private var place: DastakEnvironmentPlace = .grocery
    @State private var preset = "Day"
    @State private var closedEyes = false
    public init() {
        let args = ProcessInfo.processInfo.arguments
        _closedEyes = State(initialValue:args.contains("-DastakEnvironmentClosedEyes"))
        if let index = args.firstIndex(of:"-DastakEnvironmentPlace"), args.indices.contains(index+1),
           let initial = DastakEnvironmentPlace(rawValue:args[index+1]) { _place = State(initialValue:initial) }
        if let index = args.firstIndex(of:"-DastakEnvironmentWeather"), args.indices.contains(index+1),
           ["Day","Night","Rain","Snow"].contains(args[index+1]) { _preset = State(initialValue:args[index+1]) }
    }
    private var weather: DastakEnvironmentWeather {
        switch preset {
        case "Night": .init(daylight:0)
        case "Rain": .init(daylight:0.5,cloud:0.9,wind:22,precipitation:4)
        case "Snow": .init(daylight:0.7,cloud:0.75,wind:9,precipitation:2,snow:true)
        default: .init(daylight:1)
        }
    }
    public var body: some View {
        ZStack(alignment:.bottom) {
            DastakNativeEnvironment(place:place,weather:weather,heldEyes:closedEyes)
            VStack(alignment:.leading,spacing:12) {
                Text("Dastak · Native environment preview").font(.headline)
                Text("Local scenery only. Weather presets are simulated, not a live reading.").font(.caption)
                VStack(alignment:.leading,spacing:4) {
                    Picker("View",selection:$place) {
                        Text("Outside").tag(DastakEnvironmentPlace.outside)
                        Text("Grocery entrance").tag(DastakEnvironmentPlace.grocery)
                        Text("Grocery billing").tag(DastakEnvironmentPlace.groceryBilling)
                        Text("Café entrance").tag(DastakEnvironmentPlace.cafe)
                        Text("Café counter").tag(DastakEnvironmentPlace.cafeCounter)
                    }
                    Picker("Weather",selection:$preset) { ForEach(["Day","Night","Rain","Snow"],id:\.self) { Text($0) } }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minHeight:44)
                Button(closedEyes ? "Release eyelids" : "Hold eyelids closed") { closedEyes.toggle() }
                    .frame(minHeight:44)
            }
            .padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
            .padding(14)
        }
        .preferredColorScheme(.light)
    }
}
#endif
