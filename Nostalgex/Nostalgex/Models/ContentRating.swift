import Foundation

/// Ratings from other countries, read as the US labels the channel rules use.
///
/// Every rating rule is written in US labels: the kids and family adult gate, `contentRatings`
/// allow-lists and VHS VAULT's 9 PM `blockRatings`. Jellyfin and Emby store a certificate from
/// anywhere else with its country in front (`TmdbUtils.BuildParentalRating`: "GB-15", "GB-12A",
/// and Germany as "FSK-16"), Plex as "gb/15", and some libraries carry the bare label ("12A") or
/// "TV-12A". `usLabel` turns a label it recognises into the US label of the same age band, a film
/// label for a film and a TV label for an episode (TWEEN TV lists only TV labels, FAMILY HOUR only
/// film ones). Anything else comes back exactly as it went in, every US label included, so a US
/// library builds the same pools as before. Where a label sits between two bands it takes the
/// stricter one. The bands and labels follow Jellyfin's Localization/Ratings tables.
///
/// The item keeps its raw label for display; only the rule checks read this.
///
/// Keep in sync with `usContentRating` in scripts/nostalgex-channel-filter.cjs and
/// `NxUsContentRating` in roku/source/filter/ChannelFilter.brs. All three read
/// scripts/rating-golden.json (RatingGoldenTests here).
enum ContentRating {

    enum Band {
        case all, pg, teen, mature, adult

        var film: String {
            switch self {
            case .all: return "G"
            case .pg: return "PG"
            case .teen: return "PG-13"
            case .mature: return "R"
            case .adult: return "NC-17"
            }
        }

        var tv: String {
            switch self {
            case .all: return "TV-G"
            case .pg: return "TV-PG"
            case .teen: return "TV-14"
            case .mature, .adult: return "TV-MA"
            }
        }
    }

    /// Compared upper-cased with spaces removed, so "pg-13" or "TV-14 " is left alone too.
    static let usLabels: Set<String> = [
        "G", "PG", "PG-13", "R", "NC-17", "NR",
        "TV-Y", "TV-Y7", "TV-Y7-FV", "TV-G", "TV-PG", "TV-14", "TV-MA",
    ]

    /// Word labels by country. Numbers ("15", "FSK-16", "12+") go by age in `ageBand`, for any country.
    static let words: [String: [String: Band]] = [
        "GB": ["U": .all, "UC": .all, "PG": .pg, "12A": .teen, "12PG": .teen, "R18": .adult],
        "IE": ["G": .all, "PG": .pg, "12A": .teen, "12PG": .teen, "15A": .mature, "15PG": .mature],
        "AU": ["P": .all, "C": .all, "G": .all, "PG": .pg, "M": .mature, "MA15+": .mature,
               "AV15+": .mature, "R18+": .mature, "X18+": .adult],
        "NZ": ["G": .all, "PG": .pg, "R13": .teen, "RP13": .teen, "M": .mature, "R15": .mature,
               "R16": .mature, "RP16": .mature, "R18": .mature, "RP18": .mature, "R": .adult],
        "CA": ["C": .all, "G": .all, "C8": .pg, "PG": .pg, "14A": .teen, "18A": .mature,
               "R": .adult, "A": .adult],
        "FR": ["U": .all, "TP": .all],
        "NL": ["AL": .all, "MG6": .pg],
    ]

    /// A label with no country, or after "TV-". Only labels with one meaning everywhere;
    /// "M" and "A" mean different things in different countries.
    static let bare: [String: Band] = [
        "U": .all, "UC": .all, "12A": .teen, "12PG": .teen, "14A": .teen, "15A": .mature,
        "18A": .mature, "MA15+": .mature, "R18+": .mature, "R18": .adult, "X18+": .adult,
    ]

    /// One or two digits, then an optional "+": an age. 0 is everyone, up to 10 is PG,
    /// up to 14 is PG-13 / TV-14, older is R / TV-MA.
    static func ageBand(_ label: String) -> Band? {
        var digits = Substring(label)
        if digits.hasSuffix("+") { digits = digits.dropLast() }
        guard (1...2).contains(digits.count),
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let age = Int(digits) else { return nil }
        if age == 0 { return .all }
        if age <= 10 { return .pg }
        if age <= 14 { return .teen }
        return .mature
    }

    /// The US label the channel rules read for `raw` on an item of `type`. Returns `raw` itself
    /// (nil, "", a US label, anything unrecognised) when there is nothing to map.
    static func usLabel(_ raw: String?, type: MediaType) -> String? {
        guard let raw else { return nil }
        let key = String(raw.uppercased().filter { !$0.isWhitespace })
        if key.isEmpty || usLabels.contains(key) { return raw }

        var country: String?
        var label = key
        if key.hasPrefix("FSK") {
            country = "DE"
            label = String(key.dropFirst(3))
            if label.hasPrefix("-") { label.removeFirst() }
        } else if key.count > 3,
                  key.prefix(2).allSatisfy({ $0.isASCII && $0.isLetter }),
                  let separator = key.dropFirst(2).first, separator == "-" || separator == "/" {
            let prefix = String(key.prefix(2))
            // "TV-12A" is a bare 12A, not a country called TV.
            if prefix != "TV" { country = prefix == "UK" ? "GB" : prefix }
            label = String(key.dropFirst(3))
        }

        var band = ageBand(label)
        if band == nil {
            if let country {
                band = words[country]?[label] ?? (label == "X" ? .adult : nil)
            } else {
                band = bare[label]
            }
        }
        guard let band else { return raw }
        return type == .episode ? band.tv : band.film
    }
}
