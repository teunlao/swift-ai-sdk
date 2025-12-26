import Foundation
import SwiftAISDK

actor GenerateResultCache {
  private var store: [String: LanguageModelV3GenerateResult] = [:]

  func get(_ key: String) -> LanguageModelV3GenerateResult? { store[key] }
  func set(_ key: String, value: LanguageModelV3GenerateResult) { store[key] = value }
}

private let generateCache = GenerateResultCache()

let yourCacheMiddleware: LanguageModelV3Middleware = LanguageModelV3Middleware(
  wrapGenerate: { doGenerate, _, params, _ in
    let cacheKey = makeCacheKey(params: params)

    if let cached = await generateCache.get(cacheKey) {
      return cached
    }

    let result = try await doGenerate()
    await generateCache.set(cacheKey, value: result)
    return result
  }
  // streaming caching intentionally not implemented (mirrors upstream comment)
)

private struct CacheKey: Codable {
  let prompt: LanguageModelV3Prompt
  let maxOutputTokens: Int?
  let temperature: Double?
  let stopSequences: [String]?
  let topP: Double?
  let topK: Int?
  let presencePenalty: Double?
  let frequencyPenalty: Double?
  let responseFormat: LanguageModelV3ResponseFormat?
  let seed: Int?
  let headers: [String: String]?
  let providerOptions: SharedV3ProviderOptions?
}

private func makeCacheKey(params: LanguageModelV3CallOptions) -> String {
  let key = CacheKey(
    prompt: params.prompt,
    maxOutputTokens: params.maxOutputTokens,
    temperature: params.temperature,
    stopSequences: params.stopSequences,
    topP: params.topP,
    topK: params.topK,
    presencePenalty: params.presencePenalty,
    frequencyPenalty: params.frequencyPenalty,
    responseFormat: params.responseFormat,
    seed: params.seed,
    headers: params.headers,
    providerOptions: params.providerOptions
  )

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  if let data = try? encoder.encode(key), let string = String(data: data, encoding: .utf8) {
    return string
  }

  return UUID().uuidString
}
