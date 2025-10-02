//
//  ClusterStringsLLMTask.swift
//  AuroraToolkit
//
//  Created by Dan Murrell Jr on 1/1/25.
//

import AuroraCore
import AuroraLLM
import Foundation

/// `ClusterStringsTask` groups strings into clusters based on semantic similarity, without requiring predefined categories.
///
/// - **Inputs**
///    - `strings`: The list of strings to cluster.
///    - `maxClusters`: Optional maximum number of clusters to create. If not provided, the LLM determines the optimal number dynamically.
/// - **Outputs**
///    - `clusters`: A dictionary where keys are cluster IDs or inferred names, and values are lists of strings belonging to each cluster.
///    - `thoughts`: An array of strings containing the LLM's chain-of-thought entries, if any.
///    - `rawResponse`: The original unmodified raw response text from the LLM.
///
/// ### Use Cases:
/// - **Customer Feedback Analysis**: Grouping customer reviews or feedback to identify trends.
/// - **Content Clustering**: Organizing blog posts, news articles, or research papers into topic-based clusters.
/// - **Unsupervised Data Exploration**: Automatically grouping strings for exploratory analysis when categories are unknown.
/// - **Semantic Deduplication**: Identifying and grouping similar strings to detect duplicates or near-duplicates.
///
/// ### Example:
/// **Input Strings:**
/// - "The stock market dropped today."
/// - "AI is transforming software development."
/// - "The S&P 500 index fell by 2%."
///
/// **Output JSON:**
/// ```
/// {
///   "Cluster 1": ["The stock market dropped today.", "The S&P 500 index fell by 2%."],
///   "Cluster 2": ["AI is transforming software development."]
/// }
/// ```
public class ClusterStringsLLMTask: WorkflowComponent {
    /// The wrapped task.
    private let task: Workflow.Task
    /// Logger for debugging and monitoring.
    private let logger: CustomLogger?

    /// Initializes a new `ClusterStringsLLMTask`.
    ///
    /// - Parameters:
    ///    - name: The name of the task.
    ///    - llmService: The LLM service used for clustering.
    ///    - strings: The list of strings to cluster.
    ///    - maxClusters: Optional maximum number of clusters to create.
    ///    - maxTokens: The maximum number of tokens to generate in the response. Defaults to 500.
    ///    - inputs: Additional inputs for the task. Defaults to an empty dictionary.
    ///    - logger: Optional logger for debugging and monitoring. Defaults to `nil`.
    public init(
        name: String? = nil,
        llmService: LLMServiceProtocol,
        strings: [String]? = nil,
        maxClusters: Int? = nil,
        maxTokens: Int = 500,
        inputs: [String: Any?] = [:],
        logger: CustomLogger? = nil
    ) {
        self.logger = logger

        task = Workflow.Task(
            name: name ?? String(describing: Self.self),
            description: "Cluster strings into groups based on semantic similarity.",
            inputs: inputs
        ) { inputs in
            let resolvedStrings = inputs.resolve(key: "strings", fallback: strings) ?? []
            guard !resolvedStrings.isEmpty else {
                logger?.error("ClusterStringsLLMTask [execute] No strings provided for clustering", category: "ClusterStringsLLMTask")
                throw NSError(
                    domain: "ClusterStringsLLMTask",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No strings provided for clustering."]
                )
            }

            let resolvedMaxClusters = inputs.resolve(key: "maxClusters", fallback: maxClusters)

            // Build the prompt for the LLM
            var clusteringPrompt = """
            Cluster the following strings based on semantic similarity. Return the result as a JSON object with cluster IDs as keys and arrays of strings as values.
            Only return the JSON object, and nothing else.

            """

            if let maxClusters = resolvedMaxClusters {
                clusteringPrompt += " Limit the number of clusters to \(maxClusters)."
            }

            clusteringPrompt += """

            Example (for format illustration purposes only):
            Input Strings:
            - "The stock market dropped today."
            - "AI is transforming software development."
            - "The S&P 500 index fell by 2%."

            Output JSON:
            {
              "Cluster 1": ["The stock market dropped today.", "The S&P 500 index fell by 2%."],
              "Cluster 2": ["AI is transforming software development."]
            }

            Important Instructions:
            1. Do not include any other text, examples, or explanations in the output.
            2. Only return the JSON object with cluster IDs and string arrays.
            3. Ensure that the clusters are meaningful and relevant.
            4. Cluster the strings based on **semantic meaning and context**. Strings that describe similar topics, themes, or ideas should belong to the same cluster. For example:
                - Group strings about technology or artificial intelligence together.
                - Group strings about finance, economy, or stock markets together.
            5. Ensure the JSON object is properly formatted and valid.
            6. Ensure the JSON object is properly terminated and complete. Do not cut off or truncate the response.
            7. Do not include anything else, like markdown notation around it or any extraneous characters. The ONLY thing you should return is properly formatted, valid JSON and absolutely nothing else.
            8. Only process the following texts:

            \(resolvedStrings.joined(separator: "\n"))
            """

            let request = LLMRequest(
                messages: [
                    LLMMessage(role: .system, content: "You are an expert in semantic similarity clustering. Do NOT reveal any reasoning or chain-of-thought. Always respond with a single valid JSON object and nothing else (no markdown, explanations, or code fences)."),
                    LLMMessage(role: .user, content: clusteringPrompt),
                ],
                maxTokens: maxTokens
            )

            do {
                let response = try await llmService.sendRequest(request)

                let fullResponse = response.text
                let (thoughts, rawResponse) = fullResponse.extractThoughtsAndStripJSON()

                guard let data = rawResponse.data(using: .utf8),
                      let clusters = try? JSONSerialization.jsonObject(with: data) as? [String: [String]]
                else {
                    logger?.error("ClusterStringsLLMTask [execute] Failed to parse JSON response: \(rawResponse)", category: "ClusterStringsLLMTask")
                    throw NSError(
                        domain: "ClusterStringsLLMTask",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse LLM response as JSON."]
                    )
                }
                return [
                    "clusters": clusters,
                    "thoughts": thoughts,
                    "rawResponse": fullResponse,
                ]
            } catch {
                throw error
            }
        }
    }

    /// Converts this `ClusterStringsLLMTask` to a `Workflow.Component`.
    public func toComponent() -> Workflow.Component {
        .task(task)
    }
}
