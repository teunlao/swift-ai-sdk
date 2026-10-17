import Foundation
import AISDKProvider
import AISDKProviderUtils

struct VideoAPIError: Decodable, Sendable {
    let code: String?
    let message: String
    let requestId: String?
    private enum CodingKeys: String, CodingKey { case code, message, requestId = "request_id" }
}

let videoFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<VideoAPIError>.codable(VideoAPIError.self, jsonSchema: ["type": "object"])),
    errorToMessage: { $0.message }
)

struct VideoCreateTaskResponse: Decodable, Sendable {
    struct Output: Decodable, Sendable {
        let taskStatus: String
        let taskId: String
        private enum CodingKeys: String, CodingKey { case taskStatus = "task_status", taskId = "task_id" }
    }
    let output: Output?
    let requestId: String?
    let raw: JSONValue
    private enum CodingKeys: String, CodingKey { case output, requestId = "request_id" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        output = try container.decodeIfPresent(Output.self, forKey: .output)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        let fields = try JSONObject(from: decoder)
        var parsed = fields.filter { $0.key == "output" || $0.key == "request_id" }
        if case .object(let output) = parsed["output"] {
            parsed["output"] = .object(output.filter { $0.key == "task_status" || $0.key == "task_id" })
        }
        raw = .object(parsed)
    }
}

struct VideoTaskStatusResponse: Decodable, Sendable {
    struct Output: Decodable, Sendable {
        let taskId: String
        let taskStatus: String
        let videoUrl: String?
        let submitTime: String?
        let scheduledTime: String?
        let endTime: String?
        let origPrompt: String?
        let actualPrompt: String?
        let code: String?
        let message: String?
        private enum CodingKeys: String, CodingKey {
            case taskId = "task_id", taskStatus = "task_status", videoUrl = "video_url"
            case submitTime = "submit_time", scheduledTime = "scheduled_time", endTime = "end_time"
            case origPrompt = "orig_prompt", actualPrompt = "actual_prompt", code, message
        }
    }
    struct Usage: Decodable, Sendable {
        let fields: JSONObject
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case duration, outputVideoDuration = "output_video_duration", inputVideoDuration = "input_video_duration"
            case fps, resolution = "SR", size, ratio
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            for key in [CodingKeys.duration, .outputVideoDuration, .inputVideoDuration, .fps, .resolution] {
                _ = try container.decodeIfPresent(Double.self, forKey: key)
            }
            _ = try container.decodeIfPresent(String.self, forKey: .size)
            _ = try container.decodeIfPresent(String.self, forKey: .ratio)
            let raw = try JSONObject(from: decoder)
            let known = Set(CodingKeys.allCases.map(\.rawValue))
            fields = raw.filter { known.contains($0.key) }
        }
    }
    let output: Output?
    let usage: Usage?
    let requestId: String?
    private enum CodingKeys: String, CodingKey { case output, usage, requestId = "request_id" }
}

let videoCreateTaskSchema = FlexibleSchema(
    Schema<VideoCreateTaskResponse>.codable(VideoCreateTaskResponse.self, jsonSchema: ["type": "object"])
)
let videoTaskStatusSchema = FlexibleSchema(
    Schema<VideoTaskStatusResponse>.codable(VideoTaskStatusResponse.self, jsonSchema: ["type": "object"])
)

struct VideoGenerationError: AISDKError, Sendable {
    static let errorDomain = "vercel.ai.error"
    let name = "ALIBABA_VIDEO_GENERATION_ERROR"
    let message: String
    let cause: (any Error)? = nil
}
