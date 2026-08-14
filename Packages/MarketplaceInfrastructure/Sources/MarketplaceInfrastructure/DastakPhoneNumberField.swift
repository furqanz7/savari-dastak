import Foundation
import SwiftUI

struct DastakCallingCode: Identifiable, Hashable, Sendable {
    let regionCode: String
    let dialCode: String

    var id: String { regionCode }

    var name: String {
        Locale.current.localizedString(forRegionCode: regionCode) ?? regionCode
    }

    var flag: String {
        regionCode.unicodeScalars.reduce(into: "") { result, scalar in
            guard let regionalIndicator = UnicodeScalar(127_397 + scalar.value) else { return }
            result.unicodeScalars.append(regionalIndicator)
        }
    }

    static let india = DastakCallingCode(regionCode: "IN", dialCode: "+91")

    static let all: [DastakCallingCode] = callingCodes
        .map { DastakCallingCode(regionCode: $0.key, dialCode: $0.value) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    static func matching(_ value: String, preferredRegionCode: String = "IN") -> DastakCallingCode {
        let compact = value.filter { $0 == "+" || $0.isNumber }
        let candidates = all.filter { compact.hasPrefix($0.dialCode) }
        guard let longestCodeLength = candidates.map(\.dialCode.count).max() else {
            return all.first(where: { $0.regionCode == preferredRegionCode }) ?? .india
        }
        let longestMatches = candidates.filter { $0.dialCode.count == longestCodeLength }
        if let preferred = longestMatches.first(where: { $0.regionCode == preferredRegionCode }) {
            return preferred
        }
        if let primaryRegion = primaryRegionByDialCode[longestMatches[0].dialCode],
           let primary = longestMatches.first(where: { $0.regionCode == primaryRegion }) {
            return primary
        }
        return longestMatches[0]
    }

    private static let primaryRegionByDialCode: [String: String] = [
        "+1": "US", "+7": "RU", "+39": "IT", "+44": "GB", "+47": "NO",
        "+61": "AU", "+262": "RE", "+358": "FI", "+500": "FK", "+590": "GP",
        "+599": "CW", "+672": "AQ"
    ]

    private static let callingCodes: [String: String] = [
        "AC": "+247", "AD": "+376", "AE": "+971", "AF": "+93", "AG": "+1",
        "AI": "+1", "AL": "+355", "AM": "+374", "AO": "+244", "AQ": "+672",
        "AR": "+54", "AS": "+1", "AT": "+43", "AU": "+61", "AW": "+297",
        "AX": "+358", "AZ": "+994", "BA": "+387", "BB": "+1", "BD": "+880",
        "BE": "+32", "BF": "+226", "BG": "+359", "BH": "+973", "BI": "+257",
        "BJ": "+229", "BL": "+590", "BM": "+1", "BN": "+673", "BO": "+591",
        "BQ": "+599", "BR": "+55", "BS": "+1", "BT": "+975", "BV": "+47",
        "BW": "+267", "BY": "+375", "BZ": "+501", "CA": "+1", "CC": "+61",
        "CD": "+243", "CF": "+236", "CG": "+242", "CH": "+41", "CI": "+225",
        "CK": "+682", "CL": "+56", "CM": "+237", "CN": "+86", "CO": "+57",
        "CR": "+506", "CU": "+53", "CV": "+238", "CW": "+599", "CX": "+61",
        "CY": "+357", "CZ": "+420", "DE": "+49", "DJ": "+253", "DK": "+45",
        "DM": "+1", "DO": "+1", "DZ": "+213", "EC": "+593", "EE": "+372",
        "EG": "+20", "EH": "+212", "ER": "+291", "ES": "+34", "ET": "+251",
        "FI": "+358", "FJ": "+679", "FK": "+500", "FM": "+691", "FO": "+298",
        "FR": "+33", "GA": "+241", "GB": "+44", "GD": "+1", "GE": "+995",
        "GF": "+594", "GG": "+44", "GH": "+233", "GI": "+350", "GL": "+299",
        "GM": "+220", "GN": "+224", "GP": "+590", "GQ": "+240", "GR": "+30",
        "GS": "+500", "GT": "+502", "GU": "+1", "GW": "+245", "GY": "+592",
        "HK": "+852", "HM": "+672", "HN": "+504", "HR": "+385", "HT": "+509",
        "HU": "+36", "ID": "+62", "IE": "+353", "IL": "+972", "IM": "+44",
        "IN": "+91", "IO": "+246", "IQ": "+964", "IR": "+98", "IS": "+354",
        "IT": "+39", "JE": "+44", "JM": "+1", "JO": "+962", "JP": "+81",
        "KE": "+254", "KG": "+996", "KH": "+855", "KI": "+686", "KM": "+269",
        "KN": "+1", "KP": "+850", "KR": "+82", "KW": "+965", "KY": "+1",
        "KZ": "+7", "LA": "+856", "LB": "+961", "LC": "+1", "LI": "+423",
        "LK": "+94", "LR": "+231", "LS": "+266", "LT": "+370", "LU": "+352",
        "LV": "+371", "LY": "+218", "MA": "+212", "MC": "+377", "MD": "+373",
        "ME": "+382", "MF": "+590", "MG": "+261", "MH": "+692", "MK": "+389",
        "ML": "+223", "MM": "+95", "MN": "+976", "MO": "+853", "MP": "+1",
        "MQ": "+596", "MR": "+222", "MS": "+1", "MT": "+356", "MU": "+230",
        "MV": "+960", "MW": "+265", "MX": "+52", "MY": "+60", "MZ": "+258",
        "NA": "+264", "NC": "+687", "NE": "+227", "NF": "+672", "NG": "+234",
        "NI": "+505", "NL": "+31", "NO": "+47", "NP": "+977", "NR": "+674",
        "NU": "+683", "NZ": "+64", "OM": "+968", "PA": "+507", "PE": "+51",
        "PF": "+689", "PG": "+675", "PH": "+63", "PK": "+92", "PL": "+48",
        "PM": "+508", "PN": "+64", "PR": "+1", "PS": "+970", "PT": "+351",
        "PW": "+680", "PY": "+595", "QA": "+974", "RE": "+262", "RO": "+40",
        "RS": "+381", "RU": "+7", "RW": "+250", "SA": "+966", "SB": "+677",
        "SC": "+248", "SD": "+249", "SE": "+46", "SG": "+65", "SH": "+290",
        "SI": "+386", "SJ": "+47", "SK": "+421", "SL": "+232", "SM": "+378",
        "SN": "+221", "SO": "+252", "SR": "+597", "SS": "+211", "ST": "+239",
        "SV": "+503", "SX": "+1", "SY": "+963", "SZ": "+268", "TC": "+1",
        "TD": "+235", "TF": "+262", "TG": "+228", "TH": "+66", "TJ": "+992",
        "TK": "+690", "TL": "+670", "TM": "+993", "TN": "+216", "TO": "+676",
        "TR": "+90", "TT": "+1", "TV": "+688", "TW": "+886", "TZ": "+255",
        "UA": "+380", "UG": "+256", "UM": "+1", "US": "+1", "UY": "+598",
        "UZ": "+998", "VA": "+39", "VC": "+1", "VE": "+58", "VG": "+1",
        "VI": "+1", "VN": "+84", "VU": "+678", "WF": "+681", "WS": "+685",
        "XK": "+383", "YE": "+967", "YT": "+262", "ZA": "+27", "ZM": "+260",
        "ZW": "+263"
    ]
}

struct DastakPhoneNumberParts: Equatable, Sendable {
    let country: DastakCallingCode
    let nationalNumber: String

    static func parse(_ value: String, preferredRegionCode: String = "IN") -> Self {
        let compact = value.filter { $0 == "+" || $0.isNumber }
        let country = DastakCallingCode.matching(compact, preferredRegionCode: preferredRegionCode)
        let nationalNumber = compact.hasPrefix(country.dialCode)
            ? String(compact.dropFirst(country.dialCode.count)).filter(\.isNumber)
            : compact.filter(\.isNumber)
        return Self(country: country, nationalNumber: nationalNumber)
    }

    static func canonical(country: DastakCallingCode, nationalNumber: String) -> String {
        let maximumLength = max(0, 15 - country.dialCode.filter(\.isNumber).count)
        return country.dialCode + String(nationalNumber.filter(\.isNumber).prefix(maximumLength))
    }
}

struct DastakPhoneNumberField: View {
    @Binding private var phoneNumber: String
    @State private var selectedCountry: DastakCallingCode
    @State private var nationalNumber: String
    @State private var showsCountryPicker = false

    init(phoneNumber: Binding<String>) {
        _phoneNumber = phoneNumber
        let parts = DastakPhoneNumberParts.parse(phoneNumber.wrappedValue)
        _selectedCountry = State(initialValue: parts.country)
        _nationalNumber = State(initialValue: parts.nationalNumber)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { showsCountryPicker = true } label: {
                HStack(spacing: 7) {
                    Text(selectedCountry.flag)
                    Text(selectedCountry.dialCode)
                        .font(.body.monospacedDigit())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Country or region, \(selectedCountry.name), \(selectedCountry.dialCode)")

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 30)

#if os(iOS)
            TextField("Phone number", text: nationalNumberBinding)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .foregroundStyle(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
                .tint(Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255))
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
#else
            TextField("Phone number", text: nationalNumberBinding)
                .foregroundStyle(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
#endif
        }
        .background(Color(red: 24 / 255, green: 23 / 255, blue: 22 / 255))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showsCountryPicker) {
            DastakCountryCodePicker(selectedCountry: $selectedCountry)
                .onDisappear { synchronizePhoneNumber() }
#if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
#endif
                .preferredColorScheme(.dark)
        }
        .onChange(of: selectedCountry) { _ in synchronizePhoneNumber() }
    }

    private var nationalNumberBinding: Binding<String> {
        Binding(
            get: { nationalNumber },
            set: { newValue in
                let maximumLength = max(0, 15 - selectedCountry.dialCode.filter(\.isNumber).count)
                nationalNumber = String(newValue.filter(\.isNumber).prefix(maximumLength))
                synchronizePhoneNumber()
            }
        )
    }

    private func synchronizePhoneNumber() {
        phoneNumber = DastakPhoneNumberParts.canonical(
            country: selectedCountry,
            nationalNumber: nationalNumber
        )
    }
}

private struct DastakCountryCodePicker: View {
    @Binding var selectedCountry: DastakCallingCode
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button {
                    selectedCountry = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag).font(.title3)
                        Text(country.name).foregroundStyle(.primary)
                        Spacer()
                        Text(country.dialCode)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if country == selectedCountry {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Country or region")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $searchText, prompt: "Search country or code")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filteredCountries: [DastakCallingCode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return DastakCallingCode.all }
        return DastakCallingCode.all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.regionCode.localizedCaseInsensitiveContains(query)
                || $0.dialCode.contains(query)
        }
    }
}
