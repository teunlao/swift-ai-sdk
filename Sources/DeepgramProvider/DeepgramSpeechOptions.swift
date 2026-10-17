import Foundation
import AISDKProviderUtils

public struct DeepgramSpeechModelOptions: Codable, Sendable, Equatable {
    public enum BitRate: Codable, Sendable, Equatable {
        case number(Double)
        case string(String)
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Double.self) { self = .number(number) }
            else { self = .string(try value.decode(String.self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self { case .number(let number): try value.encode(number); case .string(let string): try value.encode(string) }
        }
    }
    public enum CallbackMethod: String, Codable, Sendable { case post = "POST", put = "PUT" }
    public enum Tag: Codable, Sendable, Equatable {
        case single(String)
        case multiple([String])
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) { self = .single(string) }
            else { self = .multiple(try value.decode([String].self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self { case .single(let string): try value.encode(string); case .multiple(let strings): try value.encode(strings) }
        }
    }
    public var bitRate: BitRate?
    public var container: String?
    public var encoding: String?
    public var sampleRate: Double?
    public var callback: String?
    public var callbackMethod: CallbackMethod?
    public var mipOptOut: Bool?
    public var tag: Tag?
    public init() {}
    private enum CodingKeys: String, CodingKey { case bitRate, container, encoding, sampleRate, callback, callbackMethod, mipOptOut, tag }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bitRate = try values.decodeIfPresent(BitRate.self, forKey: .bitRate)
        container = try values.decodeIfPresent(String.self, forKey: .container)
        encoding = try values.decodeIfPresent(String.self, forKey: .encoding)
        sampleRate = try values.decodeIfPresent(Double.self, forKey: .sampleRate)
        callback = try values.decodeIfPresent(String.self, forKey: .callback)
        callbackMethod = try values.decodeIfPresent(CallbackMethod.self, forKey: .callbackMethod)
        mipOptOut = try values.decodeIfPresent(Bool.self, forKey: .mipOptOut)
        tag = try values.decodeIfPresent(Tag.self, forKey: .tag)
        if let callback {
            guard let url = URL(string: callback), let scheme = url.scheme, !scheme.isEmpty,
                  !["http", "https", "ftp", "ws", "wss"].contains(scheme.lowercased()) || url.host?.isEmpty == false else {
                throw DecodingError.dataCorruptedError(forKey: .callback, in: values, debugDescription: "Expected a URL")
            }
        }
    }
}

let deepgramSpeechModelOptionsSchema = FlexibleSchema(
    Schema<DeepgramSpeechModelOptions>.codable(DeepgramSpeechModelOptions.self, jsonSchema: ["type": "object"])
)
