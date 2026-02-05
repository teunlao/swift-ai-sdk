import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Public exports for the generate-video module.

 Port of `@ai-sdk/ai/src/generate-video/index.ts`.
 */
public typealias Experimental_GenerateVideoResult = GenerateVideoResult

/// Experimental generate video entry point (mirrors upstream export name).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func experimental_generateVideo(
    model: VideoModel,
    prompt: GenerateVideoPrompt,
    n: Int = 1,
    maxVideosPerCall: Int? = nil,
    aspectRatio: String? = nil,
    resolution: String? = nil,
    duration: Int? = nil,
    fps: Int? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateVideoResult {
    try await generateVideo(
        model: model,
        prompt: prompt,
        n: n,
        maxVideosPerCall: maxVideosPerCall,
        aspectRatio: aspectRatio,
        resolution: resolution,
        duration: duration,
        fps: fps,
        seed: seed,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}

/// Convenience overload for plain text prompts.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func experimental_generateVideo(
    model: VideoModel,
    prompt: String,
    n: Int = 1,
    maxVideosPerCall: Int? = nil,
    aspectRatio: String? = nil,
    resolution: String? = nil,
    duration: Int? = nil,
    fps: Int? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateVideoResult {
    try await generateVideo(
        model: model,
        prompt: .text(prompt),
        n: n,
        maxVideosPerCall: maxVideosPerCall,
        aspectRatio: aspectRatio,
        resolution: resolution,
        duration: duration,
        fps: fps,
        seed: seed,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}

