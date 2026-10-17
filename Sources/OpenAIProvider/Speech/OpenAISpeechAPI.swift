struct OpenAISpeechAPITypes: Sendable, Equatable {
    enum Voice: String, Sendable {
        case alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse
    }
    enum ResponseFormat: String, Sendable {
        case mp3, opus, aac, flac, wav, pcm
    }
    var voice: Voice?
    var speed: Double?
    var responseFormat: ResponseFormat?
    var instructions: String?
}
