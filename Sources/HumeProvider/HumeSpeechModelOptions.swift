import Foundation
import AISDKProviderUtils

public struct HumeSpeechModelOptions: Codable, Sendable, Equatable {
    public enum Voice: Codable, Sendable, Equatable {
        public enum Provider: String, Codable, Sendable { case humeAI = "HUME_AI", customVoice = "CUSTOM_VOICE" }
        case id(String, provider: Provider? = nil)
        case name(String, provider: Provider? = nil)
        private enum Keys: String, CodingKey { case id, name, provider }
        public init(from decoder: Decoder) throws {
            let value = try decoder.container(keyedBy: Keys.self)
            let provider = value.contains(.provider) ? try value.decode(Provider.self, forKey: .provider) : nil
            if let id = try? value.decode(String.self, forKey: .id) { self = .id(id, provider: provider) }
            else { self = .name(try value.decode(String.self, forKey: .name), provider: provider) }
        }
        public func encode(to encoder: Encoder) throws {
            var value = encoder.container(keyedBy: Keys.self)
            switch self {
            case .id(let id, let provider): try value.encode(id, forKey: .id); try value.encodeIfPresent(provider, forKey: .provider)
            case .name(let name, let provider): try value.encode(name, forKey: .name); try value.encodeIfPresent(provider, forKey: .provider)
            }
        }
    }
    public struct Utterance: Codable, Sendable, Equatable {
        public var text: String
        public var description: String?
        public var speed: Double?
        public var trailingSilence: Double?
        public var voice: Voice?
        public init(text: String, description: String? = nil, speed: Double? = nil, trailingSilence: Double? = nil, voice: Voice? = nil) {
            self.text = text; self.description = description; self.speed = speed; self.trailingSilence = trailingSilence; self.voice = voice
        }
        private enum CodingKeys: String, CodingKey { case text, description, speed, trailingSilence, voice }
        public init(from decoder: Decoder) throws {
            let value = try decoder.container(keyedBy: CodingKeys.self)
            text = try value.decode(String.self, forKey: .text)
            description = value.contains(.description) ? try value.decode(String.self, forKey: .description) : nil
            speed = value.contains(.speed) ? try value.decode(Double.self, forKey: .speed) : nil
            trailingSilence = value.contains(.trailingSilence) ? try value.decode(Double.self, forKey: .trailingSilence) : nil
            voice = value.contains(.voice) ? try value.decode(Voice.self, forKey: .voice) : nil
        }
    }
    public enum Context: Codable, Sendable, Equatable {
        case generationId(String)
        case utterances([Utterance])
        private enum Keys: String, CodingKey { case generationId, utterances }
        public init(from decoder: Decoder) throws {
            let value = try decoder.container(keyedBy: Keys.self)
            if let id = try? value.decode(String.self, forKey: .generationId) { self = .generationId(id) }
            else { self = .utterances(try value.decode([Utterance].self, forKey: .utterances)) }
        }
        public func encode(to encoder: Encoder) throws {
            var value = encoder.container(keyedBy: Keys.self)
            switch self {
            case .generationId(let id): try value.encode(id, forKey: .generationId)
            case .utterances(let utterances): try value.encode(utterances, forKey: .utterances)
            }
        }
    }
    public var context: Context?
    public init(context: Context? = nil) { self.context = context }
}
let humeSpeechModelOptionsSchema = FlexibleSchema(Schema<HumeSpeechModelOptions>.codable(HumeSpeechModelOptions.self, jsonSchema: ["type": "object"]))
