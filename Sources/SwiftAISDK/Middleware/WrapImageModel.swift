import AISDKProvider

public typealias ImageModelMiddleware = ImageModelV4Middleware

public enum ImageModelMiddlewareInput: Sendable {
    case single(ImageModelMiddleware)
    case multiple([ImageModelMiddleware])
}

public func wrapImageModel(
    model: any ImageModelV4,
    middleware: ImageModelMiddlewareInput,
    modelId: String? = nil,
    providerId: String? = nil
) -> any ImageModelV4 {
    let middlewares: [ImageModelMiddleware]
    switch middleware {
    case .single(let value): middlewares = [value]
    case .multiple(let values): middlewares = values
    }
    return middlewares.reversed().reduce(model) {
        WrappedImageModel(model: $0, middleware: $1, modelId: modelId, providerId: providerId)
    }
}

public func wrapImageModel(
    model: any ImageModelV4,
    middleware: ImageModelMiddleware,
    modelId: String? = nil,
    providerId: String? = nil
) -> any ImageModelV4 {
    wrapImageModel(model: model, middleware: .single(middleware), modelId: modelId, providerId: providerId)
}

public func wrapImageModel(
    model: any ImageModelV4,
    middleware: [ImageModelMiddleware],
    modelId: String? = nil,
    providerId: String? = nil
) -> any ImageModelV4 {
    wrapImageModel(model: model, middleware: .multiple(middleware), modelId: modelId, providerId: providerId)
}

public func wrapImageModel(
    model: any ImageModelV3,
    middleware: ImageModelMiddlewareInput,
    modelId: String? = nil,
    providerId: String? = nil
) -> any ImageModelV4 {
    wrapImageModel(model: asImageModelV4(model), middleware: middleware, modelId: modelId, providerId: providerId)
}

private struct WrappedImageModel: ImageModelV4 {
    let model: any ImageModelV4
    let middleware: ImageModelMiddleware
    let provider: String
    let modelId: String
    let maxImagesPerCall: ImageModelV4MaxImagesPerCall
    private let fileInputs: Task<Bool?, Error>
    private let maskInputs: Task<Bool?, Error>

    init(model: any ImageModelV4, middleware: ImageModelMiddleware, modelId: String?, providerId: String?) {
        self.model = model
        self.middleware = middleware
        self.provider = providerId ?? middleware.overrideProvider?(model) ?? model.provider
        self.modelId = modelId ?? middleware.overrideModelId?(model) ?? model.modelId
        self.maxImagesPerCall = middleware.overrideMaxImagesPerCall?(model) ?? model.maxImagesPerCall
        self.fileInputs = Task {
            if let override = middleware.overrideSupportsFileInputs { return try await override(model) }
            return try await model.supportsFileInputs
        }
        self.maskInputs = Task {
            if let override = middleware.overrideSupportsMaskInputs { return try await override(model) }
            return try await model.supportsMaskInputs
        }
    }

    var supportsFileInputs: Bool? {
        get async throws { try await fileInputs.value }
    }

    var supportsMaskInputs: Bool? {
        get async throws { try await maskInputs.value }
    }

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let params = try await middleware.transformParams?(options, model) ?? options
        let generate: @Sendable () async throws -> ImageModelV4GenerateResult = {
            try await model.doGenerate(options: params)
        }
        if let wrap = middleware.wrapGenerate { return try await wrap(generate, params, model) }
        return try await generate()
    }
}
