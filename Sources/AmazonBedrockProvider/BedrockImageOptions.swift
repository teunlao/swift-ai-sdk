import AISDKProvider
import AISDKProviderUtils

public struct BedrockImageModelOptions: Codable, Sendable {
    public enum Quality: String, Codable, Sendable { case standard, premium }
    public enum Style: String, Codable, Sendable {
        case animated3D = "3D_ANIMATED_FAMILY_FILM", designSketch = "DESIGN_SKETCH", flatVector = "FLAT_VECTOR_ILLUSTRATION"
        case graphicNovel = "GRAPHIC_NOVEL_ILLUSTRATION", maximalism = "MAXIMALISM", midcenturyRetro = "MIDCENTURY_RETRO"
        case photorealism = "PHOTOREALISM", softDigitalPainting = "SOFT_DIGITAL_PAINTING"
    }
    public enum TaskType: String, Codable, Sendable {
        case textImage = "TEXT_IMAGE", imageVariation = "IMAGE_VARIATION", inpainting = "INPAINTING", outpainting = "OUTPAINTING", backgroundRemoval = "BACKGROUND_REMOVAL"
    }
    public enum OutpaintingMode: String, Codable, Sendable { case `default` = "DEFAULT", precise = "PRECISE" }
    public var quality: Quality?
    public var negativeText: String?
    public var cfgScale: Double?
    public var style: Style?
    public var taskType: TaskType?
    public var maskPrompt: String?
    public var outPaintingMode: OutpaintingMode?
    public var similarityStrength: Double?

    public init(quality: Quality? = nil, negativeText: String? = nil, cfgScale: Double? = nil, style: Style? = nil, taskType: TaskType? = nil, maskPrompt: String? = nil, outPaintingMode: OutpaintingMode? = nil, similarityStrength: Double? = nil) {
        self.quality = quality; self.negativeText = negativeText; self.cfgScale = cfgScale; self.style = style
        self.taskType = taskType; self.maskPrompt = maskPrompt; self.outPaintingMode = outPaintingMode; self.similarityStrength = similarityStrength
    }
    var json: [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        if let quality { result["quality"] = .string(quality.rawValue) }
        if let negativeText { result["negativeText"] = .string(negativeText) }
        if let cfgScale { result["cfgScale"] = .number(cfgScale) }
        if let style { result["style"] = .string(style.rawValue) }
        if let taskType { result["taskType"] = .string(taskType.rawValue) }
        if let maskPrompt { result["maskPrompt"] = .string(maskPrompt) }
        if let outPaintingMode { result["outPaintingMode"] = .string(outPaintingMode.rawValue) }
        if let similarityStrength { result["similarityStrength"] = .number(similarityStrength) }
        return result
    }
}

let bedrockImageOptionsSchema = bedrockOptionalFieldsSchema(BedrockImageModelOptions.self, fields: ["quality", "negativeText", "cfgScale", "style", "taskType", "maskPrompt", "outPaintingMode", "similarityStrength"])
