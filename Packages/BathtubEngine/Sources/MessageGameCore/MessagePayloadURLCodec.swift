import Foundation

public enum MessagePayloadURLCodec {
    private static let prefix = "data:application/vnd.tubpirates.game+json;base64,"

    public enum URLCodecError: LocalizedError, Equatable {
        case unableToCreateURL
        case unsupportedURL
        case invalidBase64

        public var errorDescription: String? {
            switch self {
            case .unableToCreateURL: "The battle link could not be created."
            case .unsupportedURL: "This is not a Tub Pirates battle link."
            case .invalidBase64: "The battle link is damaged."
            }
        }
    }

    public static func encode(_ envelope: MessageGameEnvelope) throws -> URL {
        let base64 = try MessageGameCodec.encode(envelope).base64EncodedString()
        guard let url = URL(string: prefix + base64) else { throw URLCodecError.unableToCreateURL }
        return url
    }

    public static func decode(_ url: URL) throws -> MessageGameEnvelope {
        let value = url.absoluteString
        guard value.hasPrefix(prefix) else { throw URLCodecError.unsupportedURL }
        guard let data = Data(base64Encoded: String(value.dropFirst(prefix.count))) else {
            throw URLCodecError.invalidBase64
        }
        return try MessageGameCodec.decode(data)
    }
}
