import CoreText
import MarketplaceFoundation
import SwiftUI
import WidgetKit

// These widgets contain editorial artwork and navigation only. Account, stock,
// basket and delivery state continue to come from the authenticated app.
struct DastakHomeEntry: TimelineEntry {
    let date: Date

    var greeting: String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "A fresh start."
        case 12..<17: "A little afternoon joy."
        case 17..<22: "Make an evening of it."
        default: "Your little everyday."
        }
    }
}

struct DastakHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> DastakHomeEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (DastakHomeEntry) -> Void) {
        completion(.init(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DastakHomeEntry>) -> Void) {
        let now = Date()
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        let entries = [DastakHomeEntry(date: now)] + (0..<24).map {
            DastakHomeEntry(date: hour.addingTimeInterval(Double($0) * 3600))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

enum DastakWidgetDestination: String, CaseIterable {
    case grocery, food, basket, tracking, search
    var url: URL { URL(string: "com.dastak.app://open/\(rawValue)")! }
}

struct DastakDailyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dastak.app.widget.daily", provider: DastakHomeProvider()) {
            DastakDailyWidgetView(entry: $0)
                .containerBackground(for: .widget) { DastakWidgetBackdrop(food: false) }
                .widgetURL(DastakWidgetDestination.search.url)
        }
        .configurationDisplayName("The Daily Edit")
        .description("A little Dastak, always close. Search, explore and return to your basket.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct DastakGroceryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dastak.app.widget.grocery", provider: DastakHomeProvider()) { _ in
            DastakServiceWidgetView(food: false)
                .containerBackground(for: .widget) { DastakWidgetBackdrop(food: false) }
                .widgetURL(DastakWidgetDestination.grocery.url)
        }
        .configurationDisplayName("Everyday Essentials")
        .description("A fresh little corner for your groceries. Tap to browse Dastak.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct DastakFoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dastak.app.widget.food", provider: DastakHomeProvider()) { _ in
            DastakServiceWidgetView(food: true)
                .containerBackground(for: .widget) { DastakWidgetBackdrop(food: true) }
                .widgetURL(DastakWidgetDestination.food.url)
        }
        .configurationDisplayName("Something Delicious")
        .description("Your next favourite starts here. Explore restaurants and cafés in Dastak.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct DastakSearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dastak.app.widget.search", provider: DastakHomeProvider()) { _ in
            DastakSearchAccessory()
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(DastakWidgetDestination.search.url)
        }
        .configurationDisplayName("Find with Dastak")
        .description("Open grocery and food search straight from your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private enum DastakWidgetType {
    static let cream = Color(red: 0.98, green: 0.94, blue: 0.84)
    static let mint = Color(red: 0.72, green: 0.85, blue: 0.66)
    static let gold = Color(red: 0.95, green: 0.76, blue: 0.44)
    static let ink = Color(red: 0.09, green: 0.19, blue: 0.16)

    static let registerFont: Void = {
        if let url = Bundle.main.url(forResource: "InstrumentSerif-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    static func serif(_ size: CGFloat) -> Font {
        _ = registerFont
        return .custom("InstrumentSerif-Regular", fixedSize: size)
    }
}

struct DastakWidgetBackdrop: View {
    var food: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: food
            ? [Color(red: 0.35, green: 0.18, blue: 0.14), Color(red: 0.16, green: 0.09, blue: 0.09)]
            : [Color(red: 0.16, green: 0.30, blue: 0.24), Color(red: 0.05, green: 0.14, blue: 0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay(alignment: .topTrailing) {
            Circle().fill(DastakWidgetType.gold.opacity(scheme == .dark ? 0.07 : 0.12))
                .frame(width: 210, height: 210).offset(x: 75, y: -95)
        }
    }
}

private struct DastakWidgetBrand: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Dastak").font(DastakWidgetType.serif(23))
            Text("دستک").font(.system(size: 13)).environment(\.layoutDirection, .rightToLeft)
        }
        .foregroundStyle(DastakWidgetType.cream)
        .accessibilityElement(children: .ignore).accessibilityLabel("Dastak")
    }
}

struct DastakServiceWidgetView: View {
    let food: Bool
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var wide: Bool { (previewFamily ?? family) == .systemMedium }
    private var accent: Color { food ? DastakWidgetType.gold : DastakWidgetType.mint }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if wide {
                    artwork.frame(width: geometry.size.width * 0.43, height: geometry.size.height * 0.85)
                        .position(x: geometry.size.width * 0.79, y: geometry.size.height * 0.57)
                } else {
                    artwork.frame(width: 66, height: 70)
                        .position(x: geometry.size.width * 0.79, y: geometry.size.height * 0.51)
                }
                VStack(alignment: .leading, spacing: 0) {
                    DastakWidgetBrand()
                    Spacer(minLength: 5)
                    Text(wide ? (food ? "A little\ndelicious." : "The good\neveryday.") : (food ? "Made\nfor you." : "Good\nthings."))
                        .font(DastakWidgetType.serif(wide ? 31 : 27))
                        .lineSpacing(-2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: wide ? .infinity : 80, alignment: .leading)
                        .foregroundStyle(DastakWidgetType.cream)
                    Spacer(minLength: 6)
                    HStack(spacing: 5) {
                        Text(food ? "Explore Food" : "Shop Grocery")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(accent).widgetAccentable()
                }
                .padding(16)
                .frame(width: wide ? geometry.size.width * 0.61 : geometry.size.width, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(food ? "Dastak. Explore restaurants and cafés." : "Dastak. Shop everyday groceries.")
    }

    private var artwork: some View {
        DastakWidgetIllustration(food: food, monochrome: renderingMode != .fullColor)
            .accessibilityHidden(true)
    }
}

struct DastakDailyWidgetView: View {
    let entry: DastakHomeEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var large: Bool { (previewFamily ?? family) == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 14 : 9) {
            HStack(alignment: .firstTextBaseline) {
                DastakWidgetBrand()
                Spacer()
                Text("THE DAILY EDIT").font(.system(size: 8, weight: .semibold)).tracking(1.7)
                    .foregroundStyle(DastakWidgetType.mint).widgetAccentable()
            }
            if large {
                Text(entry.greeting).font(DastakWidgetType.serif(31))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .foregroundStyle(DastakWidgetType.cream)
            }
            Link(destination: DastakWidgetDestination.search.url) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                    Text("What are you looking for?").font(.system(size: 12, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(DastakWidgetType.cream)
                .padding(.horizontal, 12).frame(height: large ? 40 : 34)
                .background(.white.opacity(0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            }.accessibilityLabel("Search groceries and food in Dastak")
            if large {
                HStack(spacing: 10) {
                    serviceTile(food: false)
                    serviceTile(food: true)
                }
                .frame(maxHeight: .infinity)
            }
            HStack(spacing: 0) {
                if !large {
                    action(.grocery, title: "Grocery", symbol: "storefront")
                    action(.food, title: "Food", symbol: "fork.knife")
                }
                action(.basket, title: "Basket", symbol: "basket")
                action(.tracking, title: "Track Order", symbol: "location.north.circle")
            }
            .padding(.top, large ? 2 : 0)
        }
        .padding(16)
        .buttonStyle(.plain)
    }

    private func action(_ destination: DastakWidgetDestination, title: String, symbol: String) -> some View {
        Link(destination: destination.url) {
            Group {
                if large {
                    HStack(spacing: 7) {
                        Image(systemName: symbol).font(.system(size: 17))
                        Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                        Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .foregroundStyle(DastakWidgetType.cream)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Open \(title) in Dastak")
    }

    private func serviceTile(food: Bool) -> some View {
        Link(destination: (food ? DastakWidgetDestination.food : .grocery).url) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(food ? "Food" : "Grocery").font(DastakWidgetType.serif(25))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(DastakWidgetType.cream)
                DastakWidgetIllustration(food: food, monochrome: renderingMode != .fullColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityHidden(true)
            }
            .padding(11)
            .background((food ? DastakWidgetType.gold : DastakWidgetType.mint).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .accessibilityLabel(food ? "Browse restaurants and cafés" : "Shop groceries")
    }
}

private struct DastakSearchAccessory: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Search Dastak", systemImage: "magnifyingglass")
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.title2).widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dastak").font(.headline)
                        Text("Find your everyday").font(.caption)
                    }
                }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "magnifyingglass").font(.title2).widgetAccentable()
                }
            }
        }.accessibilityLabel("Search groceries and food in Dastak")
    }
}

// Resolution-independent illustrations keep widgets light and crisp at every size.
// In tinted/clear mode use line art so the system cannot flatten coloured shapes
// into an unreadable solid white silhouette.
private struct DastakWidgetIllustration: View {
    let food: Bool
    var monochrome: Bool
    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 150, proxy.size.height / 120)
            Group {
                if monochrome {
                    Image(systemName: food ? "cup.and.saucer" : "basket")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.85)).widgetAccentable()
                } else if food { coffee }
                else { groceries }
            }
            .frame(width: 150, height: 120)
            .scaleEffect(scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var groceries: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.16)).frame(width: 108, height: 12).offset(y: 49)
            Capsule().fill(LinearGradient(colors: [Color(red: 0.94, green: 0.73, blue: 0.42),
                                                    Color(red: 0.72, green: 0.46, blue: 0.22)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: 24, height: 84).rotationEffect(.degrees(20)).offset(x: 27, y: -17)
                .overlay {
                    VStack(spacing: 8) {
                        ForEach(0..<3) { _ in Capsule().fill(.white.opacity(0.4)).frame(width: 15, height: 3).rotationEffect(.degrees(-20)) }
                    }.rotationEffect(.degrees(20)).offset(x: 30, y: -33)
                }
            RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.9, green: 0.94, blue: 0.83))
                .frame(width: 28, height: 60).rotationEffect(.degrees(-13)).offset(x: -24, y: -14)
            RoundedRectangle(cornerRadius: 2).fill(DastakWidgetType.mint)
                .frame(width: 20, height: 10).rotationEffect(.degrees(-13)).offset(x: -31, y: -46)
            ForEach(0..<4) { i in
                Ellipse().fill(i.isMultiple(of: 2) ? Color(red: 0.49, green: 0.65, blue: 0.36) : DastakWidgetType.mint)
                    .frame(width: 17, height: 41).rotationEffect(.degrees(Double(i * 28 - 42)))
                    .offset(x: CGFloat(i * 9 - 17), y: -33 + CGFloat(i % 2) * 7)
            }
            Path { p in
                p.move(to: CGPoint(x: 28, y: 51)); p.addLine(to: CGPoint(x: 122, y: 51))
                p.addLine(to: CGPoint(x: 113, y: 109)); p.addQuadCurve(to: CGPoint(x: 37, y: 109), control: CGPoint(x: 75, y: 116))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [DastakWidgetType.gold, Color(red: 0.73, green: 0.52, blue: 0.28)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 14).trim(from: 0.48, to: 1)
                .stroke(Color(red: 0.45, green: 0.31, blue: 0.15).opacity(0.65), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 35, height: 31).offset(y: 11)
            Image(systemName: "leaf").font(.system(size: 19, weight: .light))
                .foregroundStyle(DastakWidgetType.ink.opacity(0.8)).rotationEffect(.degrees(-15)).offset(y: 28)
        }.rotationEffect(.degrees(-5))
    }

    private var coffee: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.15)).frame(width: 113, height: 23).offset(y: 40)
            Ellipse().fill(Color(red: 0.83, green: 0.72, blue: 0.57)).frame(width: 112, height: 35).offset(y: 31)
            Ellipse().stroke(DastakWidgetType.cream.opacity(0.5), lineWidth: 2).frame(width: 92, height: 25).offset(y: 31)
            Ellipse().stroke(DastakWidgetType.cream, lineWidth: 9).frame(width: 29, height: 31).offset(x: 43, y: 6)
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: 6)
                .fill(LinearGradient(colors: [DastakWidgetType.cream, Color(red: 0.81, green: 0.72, blue: 0.58)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 79, height: 62).offset(y: 3)
            Ellipse().fill(DastakWidgetType.cream).frame(width: 79, height: 32).offset(y: -25)
            Ellipse().fill(Color(red: 0.57, green: 0.32, blue: 0.16)).frame(width: 65, height: 24).offset(y: -25)
            Image(systemName: "leaf.fill").font(.system(size: 24, weight: .light))
                .foregroundStyle(DastakWidgetType.cream).rotationEffect(.degrees(35)).scaleEffect(y: 0.6).offset(y: -25)
            HStack(spacing: 11) {
                ForEach(0..<2) { _ in
                    Path { p in
                        p.move(to: CGPoint(x: 7, y: 20)); p.addCurve(to: CGPoint(x: 7, y: 0),
                            control1: CGPoint(x: -6, y: 13), control2: CGPoint(x: 19, y: 9))
                    }.stroke(DastakWidgetType.cream.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 12, height: 20)
                }
            }.offset(y: -52)
        }.rotationEffect(.degrees(-9))
    }
}

#if DEBUG && !DASTAK_CONTROL_EXTENSION
// The exact widget views, shown locally for layout inspection without an account.
struct DastakHomeWidgetPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Dastak widgets").font(.largeTitle.bold())
                Text("Native Home Screen collection").foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    sample(width: 158, height: 158, food: false) { DastakServiceWidgetView(food: false, previewFamily: .systemSmall) }
                    sample(width: 158, height: 158, food: true) { DastakServiceWidgetView(food: true, previewFamily: .systemSmall) }
                }
                sample(width: 328, height: 158, food: false) { DastakDailyWidgetView(entry: .init(date: .now), previewFamily: .systemMedium) }
                sample(width: 328, height: 344, food: false) { DastakDailyWidgetView(entry: .init(date: .now), previewFamily: .systemLarge) }
                sample(width: 328, height: 158, food: false) { DastakServiceWidgetView(food: false, previewFamily: .systemMedium) }
                sample(width: 328, height: 158, food: true) { DastakServiceWidgetView(food: true, previewFamily: .systemMedium) }
            }.padding(20)
        }.background(Color(red: 0.08, green: 0.10, blue: 0.10)).preferredColorScheme(.dark)
    }

    private func sample<Content: View>(width: CGFloat, height: CGFloat,
                                       food: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width, height: height)
            .background(DastakWidgetBackdrop(food: food))
            .clipShape(RoundedRectangle(cornerRadius: 25))
    }
}
#endif
