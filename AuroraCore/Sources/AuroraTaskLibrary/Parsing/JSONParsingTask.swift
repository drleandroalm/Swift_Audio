//
//  JSONParsingTask.swift
//  AuroraToolkit
//
//  Created by Dan Murrell Jr on 1/13/25.
//

import AuroraCore
import Foundation
import os.log

/// `JSONParsingTask` parses a JSON blob and extracts its nested structure into a `JSONElement`.
///
/// - **Inputs**
///    - `jsonData`: The data of the JSON to parse.
/// - **Outputs**
///    - `parsedJSON`: The root `JSONElement` containing the parsed details.
///
/// This task is general-purpose and can handle any JSON structure.
public class JSONParsingTask: WorkflowComponent {
    /// The wrapped task.
    private let task: Workflow.Task
    /// An optional logger for logging task execution details.
    private let logger: CustomLogger?

    /// Initializes the `JSONParsingTask`.
    ///
    /// - Parameters:
    ///    - name: The name of the task (default is `JSONParsingTask`).
    ///    - jsonData: The JSON data to parse.
    ///    - inputs: Additional inputs for the task. Defaults to an empty dictionary.
    ///    - logger: An optional logger for logging task execution details.
    public init(
        name: String? = nil,
        jsonData: Data? = nil,
        inputs: [String: Any?] = [:],
        logger: CustomLogger? = nil
    ) {
        self.logger = logger

        task = Workflow.Task(
            name: name ?? String(describing: Self.self),
            description: "Parse JSON data into a nested structure",
            inputs: inputs
        ) { inputs in
            // Resolve the JSON data input
            let resolvedJSONData = inputs.resolve(key: "jsonData", fallback: jsonData)

            // Validate input
            guard let jsonData = resolvedJSONData, !jsonData.isEmpty else {
                logger?.error("Missing or invalid JSON data", category: "JSONParsingTask")
                throw NSError(domain: "JSONParsingTask", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid JSON data"])
            }

            // Parse the JSON data
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let jsonElement = JSONElement(from: jsonObject)

            return ["parsedJSON": jsonElement]
        }
    }

    /// Converts this `JSONParsingTask` to a `Workflow.Component`.
    public func toComponent() -> Workflow.Component {
        .task(task)
    }
}
