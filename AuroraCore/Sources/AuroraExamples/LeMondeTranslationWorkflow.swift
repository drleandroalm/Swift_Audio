//
//  LeMondeTranslationWorkflow.swift
//  AuroraToolkit
//
//  Created by Dan Murrell Jr on 12/29/24.
//

import AuroraCore
import AuroraLLM
import AuroraTaskLibrary
import Foundation

/// Example workflow demonstrating fetching news articles from Le Monde, translating them into English,
/// and summarizing them using AuroraCore.

struct LeMondeTranslationWorkflow {
    func execute() async {
        // Set up the required API key for your LLM service (e.g., OpenAI, Anthropic, or Ollama)
        let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        guard !openAIKey.isEmpty else {
            print("No API key provided. Please set the OPENAI_API_KEY environment variable.")
            return
        }

        // Initialize the LLM service
        let llmService = OpenAIService(apiKey: openAIKey, logger: CustomLogger.shared)
        let summarizer = Summarizer(llmService: llmService)

        // Workflow initialization
        var workflow = Workflow(
            name: "Le Monde Translation Workflow",
            description: "Fetch, translate, and summarize articles from Le Monde.",
            logger: CustomLogger.shared
        ) {
            // Step 1: Fetch the Le Monde RSS Feed
            FetchURLTask(name: "FetchLeMondeFeed", url: "https://www.lemonde.fr/international/rss_full.xml")

            // Step 2: Parse the feed
            RSSParsingTask(name: "ParseLeMondeFeed", inputs: ["feedData": "{FetchLeMondeFeed.data}"])

            // Step 3: Limit the number of articles to a maximum of 5
            Workflow.Task(
                name: "LatestArticles",
                inputs: ["articles": "{ParseLeMondeFeed.articles}"]
            ) { inputs in
                let articles = inputs["articles"] as? [RSSArticle] ?? []
                return ["articles": Array(articles.prefix(5))]
            }

            // Step 4: Translate each article into English
            Workflow.Task(
                name: "TranslateArticles",
                inputs: ["latestArticles": "{LatestArticles.articles}"]
            ) { inputs in
                guard let articles = inputs["latestArticles"] as? [RSSArticle] else {
                    throw NSError(domain: "TranslateArticles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid articles input"])
                }

                let articlesToTranslate = articles.map { $0.description }

                let task = TranslateStringsLLMTask(
                    llmService: llmService,
                    strings: articlesToTranslate,
                    targetLanguage: "en",
                    sourceLanguage: "fr",
                    maxTokens: 1500
                )
                guard case let .task(unwrappedTask) = task.toComponent() else {
                    throw NSError(domain: "TranslateArticles", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create TranslateStringsLLMTask."])
                }

                let outputs = try await unwrappedTask.execute()
                guard let translations = outputs["translations"] as? [String] else {
                    throw NSError(domain: "TranslateArticles", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve translations"])
                }

                return ["articles": translations]
            }

            // Step 5: Summarize the translated articles
            SummarizeStringsLLMTask(
                summarizer: summarizer,
                summaryType: .multiple,
                inputs: ["strings": "{TranslateArticles.articles}"]
            )
        }

        print("Executing \(workflow.name)...")
        print(workflow.description)

        // Execute the workflow
        await workflow.start()

        // Print the workflow outputs
        if let summaries = workflow.outputs["SummarizeStringsLLMTask.summaries"] as? [String] {
            print("Generated Summaries:\n")
            for (index, summary) in summaries.enumerated() {
                print("\(index + 1): \(summary)")
            }
        } else {
            print("No summaries generated.")
        }

        print("\n-------\n")

        let report = await workflow.generateReport()
        print(report.printedReport(compact: true, showOutputs: false))
    }
}
