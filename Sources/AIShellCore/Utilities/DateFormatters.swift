// Sources/AIShellCore/Utilities/DateFormatters.swift

import Foundation

extension ISO8601DateFormatter {
    /// ISO8601 formatter with fractional seconds support
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Standard ISO8601 formatter without fractional seconds
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension JSONDecoder {
    /// Configure decoder to handle ISO8601 dates with or without fractional seconds
    func configureDateDecoding() {
        self.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try with fractional seconds first
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: dateString) {
                return date
            }

            // Fallback to standard format
            if let date = ISO8601DateFormatter.standard.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not parse date string: \(dateString)"
            )
        }
    }
}

extension JSONEncoder {
    /// Configure encoder to output ISO8601 dates with fractional seconds
    func configureDateEncoding() {
        self.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let dateString = ISO8601DateFormatter.withFractionalSeconds.string(from: date)
            try container.encode(dateString)
        }
    }
}
