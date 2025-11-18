// Sources/AIShellCore/Utilities/DateFormatters.swift

import Foundation

/// Helper for configuring JSON date encoding/decoding with ISO8601 support
public enum DateCoding {
    /// ISO8601 formatter with fractional seconds support
    private static let formatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Standard ISO8601 formatter without fractional seconds
    private static let formatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Custom date decoding strategy that handles ISO8601 with or without fractional seconds
    public static var flexibleISO8601: JSONDecoder.DateDecodingStrategy {
        return .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try with fractional seconds first
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }

            // Fallback to standard format
            if let date = formatterStandard.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not parse date string: \(dateString). Expected ISO8601 format with or without fractional seconds."
            )
        }
    }

    /// Custom date encoding strategy that outputs ISO8601 with fractional seconds
    public static var iso8601WithFractional: JSONEncoder.DateEncodingStrategy {
        return .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let dateString = formatterWithFractional.string(from: date)
            try container.encode(dateString)
        }
    }
}
