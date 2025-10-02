//
//  RSSParsingTask.swift
//  AuroraCore
//
//  Created by Dan Murrell Jr on 12/3/24.
//

import AuroraCore
import Foundation
import os.log

/// `RSSParsingTask` parses an RSS feed and extracts the article links.
///
/// - **Inputs**
///    - `feedData`: The data of the RSS feed to parse.
/// - **Outputs**
///    - `articles`: An array of `RSSArticle` objects containing the article details.
///
/// This task can be integrated into a workflow where article links need to be extracted from an RSS feed.
public class RSSParsingTask: WorkflowComponent {
    /// The wrapped task.
    private let task: Workflow.Task
    /// An optional logger for logging task execution details.
    private let logger: CustomLogger?

    private var articleLinks: [String] = []
    private var currentElement: String = ""
    private var currentLink: String?

    /// Initializes the `RSSParsingTask` with the RSS feed data.
    ///
    /// - Parameters:
    ///    - name: The name of the task (default is `RSSParsingTask`).
    ///    - feedData: The data of the RSS feed to parse.
    ///    - inputs: Additional inputs for the task. Defaults to an empty dictionary.
    ///    - logger: An optional logger for logging task execution details.
    ///
    /// - Note: The `inputs` array can contain direct values for keys like `feedData`, or dynamic references that will be resolved at runtime.
    public init(
        name: String? = nil,
        feedData: Data? = nil,
        inputs: [String: Any?] = [:],
        logger: CustomLogger? = nil
    ) {
        self.logger = logger

        task = Workflow.Task(
            name: name ?? String(describing: Self.self),
            description: "Extract article links from the RSS feed",
            inputs: inputs
        ) { inputs in
            /// Resolve the feedData from the inputs if it exists, otherwise use the provided `feedData` parameter or default
            let resolvedFeedData = inputs.resolve(key: "feedData", fallback: feedData)

            // Validate the input data
            guard let feedData = resolvedFeedData, !feedData.isEmpty else {
                logger?.error("Missing or invalid RSS feed data", category: "RSSParsingTask")
                throw NSError(domain: "RSSParsingTask", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid RSS feed data"])
            }

            // Initialize the parser
            let parserDelegate = RSSParserDelegate()
            let parser = XMLParser(data: feedData)
            parser.delegate = parserDelegate

            // Start parsing
            guard parser.parse() else {
                let parseError = parser.parserError?.localizedDescription ?? "Unknown error"
                logger?.error("Failed to parse RSS feed: \(parseError)", category: "RSSParsingTask")
                throw NSError(domain: "RSSParsingTask", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse RSS feed: \(parseError)"])
            }

            return ["articles": parserDelegate.articles]
        }
    }

    /// Converts this `RSSParsingTask` to a `Workflow.Component`.
    public func toComponent() -> Workflow.Component {
        .task(task)
    }
}

/// `RSSArticle` represents an article extracted from an RSS feed.
public struct RSSArticle {
    /// The title of the article.
    public let title: String

    /// The link to the article.
    public let link: String

    /// The description of the article.
    public let description: String

    /// The GUID of the article.
    public let guid: String
}

/// The `RSSParserDelegate` class is responsible for parsing the RSS feed XML data.
private class RSSParserDelegate: NSObject, XMLParserDelegate {
    var articles: [RSSArticle] = []
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentDescription: String = ""
    private var currentGUID: String = ""
    private var insideItem: Bool = false

    // MARK: - XMLParserDelegate Methods

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes _: [String: String]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentLink = ""
            currentDescription = ""
            currentGUID = ""
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }

        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentElement {
        case "title":
            currentTitle += trimmedString
        case "link":
            currentLink += trimmedString
        case "description":
            currentDescription += trimmedString
        case "guid":
            currentGUID += trimmedString
        default:
            break
        }
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        if elementName == "item" {
            // Validate the article before adding. Skip if title or link is empty
            if !currentTitle.isEmpty && !currentLink.isEmpty {
                let article = RSSArticle(
                    title: currentTitle,
                    link: currentLink,
                    description: currentDescription,
                    guid: currentGUID
                )
                articles.append(article)
            }

            // Reset current variables for the next item
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentGUID = ""

            insideItem = false
        }
        currentElement = ""
    }
}
