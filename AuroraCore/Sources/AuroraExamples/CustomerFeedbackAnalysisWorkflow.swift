//
//  CustomerFeedbackAnalysisWorkflow.swift
//  AuroraToolkit
//
//  Created by Dan Murrell Jr on 1/8/25.
//

import AuroraCore
import AuroraLLM
import AuroraTaskLibrary
import Foundation

/// Example workflow demonstrating fetching customer feedback from an app store,
/// analyzing it for insights, and generating actionable suggestions.

struct CustomerFeedbackAnalysisWorkflow {
    func execute() async {
        guard let llmService = setupLLMService() else { return }
        let summarizer = Summarizer(llmService: llmService)
        var workflow = createWorkflow(llmService: llmService, summarizer: summarizer)

        await executeWorkflow(&workflow)
        await printWorkflowResults(workflow)
    }

    private func setupLLMService() -> OpenAIService? {
        let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        guard !openAIKey.isEmpty else {
            print("No API key provided. Please set the OPENAI_API_KEY environment variable.")
            return nil
        }
        return OpenAIService(apiKey: openAIKey, logger: CustomLogger.shared)
    }

    private func createWorkflow(llmService: OpenAIService, summarizer: Summarizer) -> Workflow {
        let countryCode = "us" // Change to your country code if needed
        let appId = "284708449" // Replace with your app ID, e.g. UrbanSpoon app
        let appStoreReviewsURL = "https://itunes.apple.com/\(countryCode)/rss/customerreviews/page=1/id=\(appId)/sortBy=mostRecent/json"

        return Workflow(
            name: "Customer Feedback Analysis Workflow",
            description: "Fetch, analyze, and generate insights from app store reviews.",
            logger: CustomLogger.shared
        ) {
            // Step 1: Fetch App Store Reviews
            FetchURLTask(
                name: "FetchReviews",
                url: appStoreReviewsURL
            )

            // Step 2: Parse the reviews feed
            JSONParsingTask(
                name: "ParseReviewsFeed",
                inputs: ["jsonData": "{FetchReviews.data}"]
            )

            // Step 3: Extract Review Text
            Workflow.Task(
                name: "ExtractReviewText",
                inputs: ["parsedJSON": "{ParseReviewsFeed.parsedJSON}"]
            ) { inputs in
                guard let parsedJSON = inputs["parsedJSON"] as? JSONElement,
                      let feed = parsedJSON["feed"],
                      let entries = feed["entry"]?.asArray
                else {
                    throw NSError(
                        domain: "CustomerFeedbackAnalysisWorkflow",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No reviews found in the feed."]
                    )
                }

                // Extract the review text from the JSON feed
                let reviews = entries.compactMap { entry in
                    entry["content"]?["label"]?.asString
                }

                // Limit to 10 reviews for simpler processing
                return ["strings": reviews.prefix(10)]
            }

            // Step 3: Detect Languages of the Reviews
            DetectLanguagesLLMTask(
                name: "DetectReviewLanguages",
                llmService: llmService,
                maxTokens: 1000,
                inputs: ["strings": "{ExtractReviewText.strings}"]
            )

            // Step 4: Analyze Sentiment
            AnalyzeSentimentLLMTask(
                name: "AnalyzeReviewSentiment",
                llmService: llmService,
                detailed: true,
                maxTokens: 1000,
                inputs: ["strings": "{ExtractReviewText.strings}"]
            )

            // Step 5: Extract Keywords from Reviews
            GenerateKeywordsLLMTask(
                name: "ExtractReviewKeywords",
                llmService: llmService,
                maxTokens: 1000,
                inputs: ["strings": "{ExtractReviewText.strings}"]
            )

            // Step 6: Generate Actionable Suggestions
            GenerateTitlesLLMTask(
                name: "GenerateReviewSuggestions",
                llmService: llmService,
                languages: ["en"],
                maxTokens: 1000,
                inputs: ["strings": "{ExtractReviewText.strings}"]
            )

            // Step 7: Summarize Findings
            SummarizeStringsLLMTask(
                name: "SummarizeReviewFindings",
                summarizer: summarizer,
                summaryType: .multiple,
                inputs: ["strings": "{ExtractReviewText.strings}"]
            )
        }
    }

    private func executeWorkflow(_ workflow: inout Workflow) async {
        print("Executing \(workflow.name)...")
        print(workflow.description)
        await workflow.start()
    }

    private func printWorkflowResults(_ workflow: Workflow) async {
        printSummaries(workflow)
        printLanguageAnalysis(workflow)
        printKeywordAnalysis(workflow)
        printSentimentAnalysis(workflow)
        printActionableInsights(workflow)
        await printWorkflowReport(workflow)
    }

    private func printSummaries(_ workflow: Workflow) {
        if let summaries = workflow.outputs["SummarizeReviewFindings.summaries"] as? [String] {
            print("Review Findings Summaries:")
            for (index, summary) in summaries.enumerated() {
                print("\(index + 1): \(summary)")
            }
        } else {
            print("No summaries generated.")
        }
    }

    private func printLanguageAnalysis(_ workflow: Workflow) {
        if let detectedLanguages = workflow.outputs["DetectReviewLanguages.languages"] as? [String: String] {
            let languages = detectedLanguages.values
                .reduce(into: [String: Int]()) { counts, language in
                    counts[language, default: 0] += 1
                }
                .sorted { $0.key < $1.key }
            print("\nLanguages found in reviews:")
            for (language, count) in languages {
                print("- \(language): \(count) review(s)")
            }
        }
    }

    private func printKeywordAnalysis(_ workflow: Workflow) {
        if let keywordsDict = workflow.outputs["ExtractReviewKeywords.keywords"] as? [String: [String]] {
            // Extract and display the flat list of keywords
            let keywords = Set(keywordsDict.values.flatMap { $0 }).sorted()
            print("\nKeywords found in reviews:\n- \(keywords.joined(separator: ", "))")
        }

        if let categorizedKeywords = workflow.outputs["ExtractReviewKeywords.categorizedKeywords"] as? [String: [String]] {
            // Display categorized keywords
            print("\nCategorized Keywords:")
            for (category, keywords) in categorizedKeywords.sorted(by: { $0.key < $1.key }) {
                print("- \(category): \(keywords.joined(separator: ", "))")
            }
        }
    }

    private func printSentimentAnalysis(_ workflow: Workflow) {
        if let sentiments = workflow.outputs["AnalyzeReviewSentiment.sentiments"] as? [String: [String: Any]] {
            var sentimentCounts = ["Positive": 0, "Neutral": 0, "Negative": 0]
            var sentimentExamples = ["Positive": [String](), "Neutral": [String](), "Negative": [String]()]

            for (review, sentimentInfo) in sentiments {
                guard
                    let sentiment = sentimentInfo["sentiment"] as? String,
                    let confidence = sentimentInfo["confidence"] as? Int
                else { continue }

                sentimentCounts[sentiment, default: 0] += 1

                // Add example review for each sentiment category
                if sentimentExamples[sentiment]?.count ?? 0 < 2 {
                    sentimentExamples[sentiment]?.append("\"\(review)\" (\(confidence)% confidence)")
                }
            }

            // Display sentiment analysis summary
            let totalReviews = sentiments.count
            print("\nOverall sentiment for \(totalReviews) reviews:")
            for (sentiment, count) in sentimentCounts {
                let percentage = (Double(count) / Double(totalReviews) * 100).rounded()
                print("- \(sentiment): \(Int(percentage))% (\(count) review(s))")
            }

            // Display examples for each sentiment
            print("\nSentiment examples:")
            for (sentiment, examples) in sentimentExamples {
                print("- \(sentiment):")
                examples.forEach { print("  \(String(describing: $0))") }
            }
        }
    }

    private func printActionableInsights(_ workflow: Workflow) {
        if let suggestions = workflow.outputs["GenerateReviewSuggestions.titles"] as? [String: [String: String]] {
            print("\nActionable Insights:")
            for (review, titles) in suggestions {
                for (_, title) in titles {
                    print("Insight: \(title)")
                }
                print("  Based on review: \(review)")
            }
        } else {
            print("No suggestions generated.")
        }
    }

    private func printWorkflowReport(_ workflow: Workflow) async {
        print("\n-------\n")
        let report = await workflow.generateReport()
        print(report.printedReport(compact: true, showOutputs: false))
    }
}
