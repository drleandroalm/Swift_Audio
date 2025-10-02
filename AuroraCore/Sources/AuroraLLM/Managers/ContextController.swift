//
//  ContextController.swift
//  Aurora
//
//  Created by Dan Murrell Jr on 8/21/24.
//

import AuroraCore
import Foundation

/// `ContextController` manages the state and operations related to a specific `Context`, including adding, removing, and updating items, as well as summarizing older items. The controller handles context-specific summarization using a connected LLM service.
public class ContextController {
    /// Unique identifier for the context controller.
    public let id: UUID

    /// The context managed by this controller.
    private var context: Context

    /// A collection of summarized context items.
    private var summarizedItems: [ContextItem] = []

    /// LLM service used for generating summaries.
    private var llmService: LLMServiceProtocol

    /// Summarizer instance responsible for summarizing context items.
    private var summarizer: SummarizerProtocol

    /// Optional logger for logging events and errors.
    private var logger: CustomLogger?

    /// Initializes a new `ContextController` instance.
    ///
    /// - Parameters:
    ///    - context: Optional `Context` object. If none is provided, a new context will be created automatically.
    ///    - llmService: The LLM service to be used for summarization.
    ///    - summarizer: Optional `Summarizer` instance. If none is provided, a default summarizer will be created.
    public init(
        context: Context? = nil,
        llmService: LLMServiceProtocol,
        summarizer: SummarizerProtocol? = nil,
        logger: CustomLogger? = nil
    ) {
        self.context = context ?? Context(llmServiceVendor: llmService.vendor)
        id = self.context.id // Use the context's ID as the controller ID
        self.llmService = llmService
        self.logger = logger
        self.summarizer = summarizer ?? Summarizer(llmService: llmService, logger: logger)
    }

    /// Updates the LLM service used by the `ContextController`.
    ///
    /// - Parameter newService: The new `LLMServiceProtocol` to use for summarization.
    ///
    /// This method is useful for switching between different LLM services during runtime.
    /// Note: The `Summarizer` instance will be updated to use the new LLM service.
    public func updateLLMService(_ newService: LLMServiceProtocol) {
        llmService = newService
        summarizer = Summarizer(llmService: newService) // Update summarizer to use new LLM
    }

    /// Adds a new item to the context.
    ///
    /// - Parameters:
    ///    - content: The content of the item to be added.
    ///    - creationDate: The date when the item was created. Defaults to the current date.
    ///    - isSummary: A boolean flag indicating whether the item being added is a summary. Defaults to `false`.
    public func addItem(content: String, creationDate: Date = Date(), isSummary: Bool = false) {
        context.addItem(content: content, creationDate: creationDate, isSummary: isSummary)
    }

    /// Adds a bookmark to the context for a specific item.
    ///
    /// - Parameters:
    ///    - item: The `ContextItem` to be bookmarked.
    ///    - label: A label for the bookmark.
    public func addBookmark(for item: ContextItem, label: String) {
        context.addBookmark(for: item, label: label)
    }

    /// Removes items from the context based on their offsets.
    ///
    /// - Parameter offsets: The index set of the items to be removed.
    public func removeItems(atOffsets offsets: IndexSet) {
        context.removeItems(atOffsets: offsets)
    }

    /// Updates an existing item in the context.
    ///
    /// - Parameter updatedItem: The updated `ContextItem` to replace the old item.
    public func updateItem(_ updatedItem: ContextItem) {
        context.updateItem(updatedItem)
    }

    /// Summarizes older context items based on a given age threshold.
    ///
    /// - Parameter daysThreshold: The number of days after which items are considered "old". Defaults to 7 days.
    public func summarizeOlderContext(daysThreshold: Int = 7) async throws {
        guard !context.items.isEmpty else { return }

        var group: [ContextItem] = []

        for item in context.items where !item.isSummarized && item.isOlderThan(days: daysThreshold) {
            group.append(item)
        }

        try await summarizeGroup(group)
    }

    /// Summarizes a group of context items using the connected LLM service and stores the result in `summarizedItems`.
    ///
    /// - Parameter group: The array of `ContextItem` to be summarized.
    private func summarizeGroup(_ group: [ContextItem], options: SummarizerOptions? = nil) async throws {
        guard !group.isEmpty else { return }

        // Determine if we should summarize items individually or as a group
        let summaries: [String]
        if group.count == 1 {
            // Summarize a single item
            let summary = try await summarizer.summarize(group[0].text, options: options, logger: logger)
            summaries = [summary]
        } else {
            // Summarize multiple items
            let texts = group.map { $0.text }
            summaries = try await summarizer.summarizeGroup(texts, type: .single, options: options, logger: logger)
        }

        // Create a new summary item
        for summary in summaries {
            let summaryItem = ContextItem(text: summary, isSummary: true)
            summarizedItems.append(summaryItem)
        }

        // Mark the original items as summarized
        for item in group {
            var updatedItem = item
            updatedItem.isSummarized = true
            context.updateItem(updatedItem)
        }
    }

    /// Retrieves the full history of context items.
    ///
    /// - Returns: An array of `ContextItem` representing the full history.
    public func fullHistory() -> [ContextItem] {
        return context.items
    }

    /// Retrieves the summarized context items.
    ///
    /// - Returns: An array of `ContextItem` representing the summarized items.
    public func summarizedContext() -> [ContextItem] {
        return summarizedItems
    }

    /// Exposes the context items for testing purposes.
    ///
    /// - Returns: An array of `ContextItem`.
    public func getItems() -> [ContextItem] {
        return context.items
    }

    /// Exposes the bookmarks for testing purposes.
    ///
    /// - Returns: An array of `Bookmark`.
    public func getBookmarks() -> [Bookmark] {
        return context.bookmarks
    }

    /// Exposes the underlying context for testing or external use.
    ///
    /// - Returns: The `Context` instance.
    public func getContext() -> Context {
        var contextToReturn = context
        contextToReturn.llmServiceVendor = llmService.vendor
        return contextToReturn
    }

    /// Exposes the llmService used by the `ContextController`.
    ///
    /// - Returns: The `LLMServiceProtocol` instance.
    public func getLLMService() -> LLMServiceProtocol {
        return llmService
    }

    /// Exposes the summarizer used by the `ContextController`.
    ///
    /// - Returns: The `Summarizer` instance.
    public func getSummarizer() -> SummarizerProtocol {
        return summarizer
    }
}
