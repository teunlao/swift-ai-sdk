import Foundation
import AISDKProvider
import AISDKProviderUtils

private let googleCodeExecutionInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "language": .object([
                    "type": .string("string"),
                    "description": .string("The programming language of the code.")
                ]),
                "code": .object([
                    "type": .string("string"),
                    "description": .string("The code to be executed.")
                ])
            ]),
            "required": .array([
                .string("language"),
                .string("code")
            ])
        ])
    )
)

private let googleCodeExecutionOutputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "outcome": .object([
                    "type": .string("string"),
                    "description": .string("The outcome of the execution (e.g., \"OUTCOME_OK\").")
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("The output from the code execution.")
                ])
            ]),
            "required": .array([
                .string("outcome"),
                .string("output")
            ])
        ])
    )
)

public let googleCodeExecutionToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "google.code_execution",
    name: "code_execution",
    inputSchema: googleCodeExecutionInputSchema,
    outputSchema: googleCodeExecutionOutputSchema
)

@discardableResult
public func googleCodeExecutionTool() -> Tool {
    googleCodeExecutionToolFactory(ProviderToolFactoryWithOutputSchemaOptions(args: [:]))
}
