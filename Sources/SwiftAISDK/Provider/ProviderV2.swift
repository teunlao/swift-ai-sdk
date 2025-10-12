/**
 Provider for language, text embedding, and image generation models.

 Port of `@ai-sdk/provider/src/provider/v2/provider-v2.ts`.
 */
public protocol ProviderV2: Sendable {
    /**
     Returns the language model with the given id.
     The model id is then passed to the provider function to get the model.

     - Parameter modelId: The id of the model to return.
     - Returns: The language model associated with the id.
     - Throws: `NoSuchModelError` if no such model exists.
     */
    func languageModel(modelId: String) -> any LanguageModelV2

    /**
     Returns the text embedding model with the given id.
     The model id is then passed to the provider function to get the model.

     - Parameter modelId: The id of the model to return.
     - Returns: The text embedding model associated with the id.
     - Throws: `NoSuchModelError` if no such model exists.
     */
    func textEmbeddingModel(modelId: String) -> any EmbeddingModelV2<String>

    /**
     Returns the image model with the given id.
     The model id is then passed to the provider function to get the model.

     - Parameter modelId: The id of the model to return.
     - Returns: The image model associated with the id.
     - Throws: `NoSuchModelError` if no such model exists.
     */
    func imageModel(modelId: String) -> any ImageModelV2

    /**
     Returns the transcription model with the given id.
     The model id is then passed to the provider function to get the model.

     - Parameter modelId: The id of the model to return.
     - Returns: The transcription model associated with the id, or `nil` if not supported.
     */
    func transcriptionModel(modelId: String) -> (any TranscriptionModelV2)?

    /**
     Returns the speech model with the given id.
     The model id is then passed to the provider function to get the model.

     - Parameter modelId: The id of the model to return.
     - Returns: The speech model associated with the id, or `nil` if not supported.
     */
    func speechModel(modelId: String) -> (any SpeechModelV2)?
}

extension ProviderV2 {
    /// Default implementation returns `nil` (transcription not supported)
    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV2)? {
        return nil
    }

    /// Default implementation returns `nil` (speech not supported)
    public func speechModel(modelId: String) -> (any SpeechModelV2)? {
        return nil
    }
}
