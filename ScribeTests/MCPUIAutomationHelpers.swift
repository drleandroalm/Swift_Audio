import Foundation
import XCTest

/// Self-healing UI automation helpers using MCP's describe_ui()
/// These helpers dynamically discover UI elements instead of hardcoding coordinates
/// making tests resilient to layout changes and cross-platform differences

// MARK: - UI Element Types

struct UIElement: Codable {
    let id: String
    let type: String
    let label: String
    let value: String?
    let frame: CGRect
    let isEnabled: Bool
    let isVisible: Bool

    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

struct UIHierarchy: Codable {
    let timestamp: Date
    let elements: [UIElement]
    let screenSize: CGSize

    func findElement(type: String? = nil, label: String? = nil, value: String? = nil, predicate: ((UIElement) -> Bool)? = nil) -> UIElement? {
        elements.first { element in
            var matches = element.isVisible && element.isEnabled

            if let type = type {
                matches = matches && element.type == type
            }

            if let label = label {
                matches = matches && element.label.contains(label)
            }

            if let value = value {
                matches = matches && (element.value?.contains(value) ?? false)
            }

            if let predicate = predicate {
                matches = matches && predicate(element)
            }

            return matches
        }
    }

    func hasElement(type: String? = nil, label: String? = nil, minHeight: CGFloat? = nil) -> Bool {
        elements.contains { element in
            var matches = element.isVisible

            if let type = type {
                matches = matches && element.type == type
            }

            if let label = label {
                matches = matches && element.label.contains(label)
            }

            if let minHeight = minHeight {
                matches = matches && element.frame.height >= minHeight
            }

            return matches
        }
    }

    func hasText(_ text: String) -> Bool {
        elements.contains { element in
            element.label.contains(text) || (element.value?.contains(text) ?? false)
        }
    }
}

// MARK: - MCP UI Automation Helper

@available(macOS 13.0, iOS 16.0, *)
class MCPUIAutomationHelper {
    let simulatorUuid: String
    private var lastUISnapshot: UIHierarchy?

    init(simulatorUuid: String) {
        self.simulatorUuid = simulatorUuid
    }

    // MARK: - UI Discovery

    /// Fetch current UI hierarchy (should call MCP describe_ui tool)
    /// NOTE: In actual implementation, this would call the MCP tool
    /// For now, this is a placeholder that tests can mock
    func describeUI() async throws -> UIHierarchy {
        // In real implementation:
        // let result = await mcp.describe_ui(simulatorUuid: simulatorUuid)
        // return try JSONDecoder().decode(UIHierarchy.self, from: result)

        // Placeholder for testing
        throw MCPError.notImplemented("describe_ui MCP call not yet integrated")
    }

    /// Find element by label (supports partial matching)
    func findElement(label: String) async throws -> UIElement? {
        let ui = try await describeUI()
        return ui.findElement(label: label)
    }

    /// Find button by label
    func findButton(_ label: String) async throws -> UIElement? {
        let ui = try await describeUI()
        return ui.findElement(type: "Button", label: label)
    }

    /// Find text field by label or placeholder
    func findTextField(_ labelOrPlaceholder: String) async throws -> UIElement? {
        let ui = try await describeUI()
        return ui.findElement(type: "TextField", label: labelOrPlaceholder)
    }

    // MARK: - UI Actions

    /// Tap element by label (self-healing)
    func tapElement(label: String, timeout: TimeInterval = 5.0) async throws {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if let element = try await findElement(label: label) {
                try await tap(at: element.center)
                try await waitForAnimation(0.3)
                return
            }

            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        throw MCPError.elementNotFound("Element with label '\(label)' not found within \(timeout)s")
    }

    /// Tap button (self-healing)
    func tapButton(_ label: String, timeout: TimeInterval = 5.0) async throws {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if let button = try await findButton(label) {
                try await tap(at: button.center)
                try await waitForAnimation(0.3)
                return
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw MCPError.elementNotFound("Button '\(label)' not found within \(timeout)s")
    }

    /// Wait for element to appear
    func waitForElement(label: String, timeout: TimeInterval = 10.0) async throws -> UIElement {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if let element = try await findElement(label: label) {
                return element
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw MCPError.timeout("Element '\(label)' did not appear within \(timeout)s")
    }

    /// Wait for element to disappear
    func waitForElementToDisappear(label: String, timeout: TimeInterval = 10.0) async throws {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if try await findElement(label: label) == nil {
                return
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw MCPError.timeout("Element '\(label)' did not disappear within \(timeout)s")
    }

    /// Wait for animation to complete
    func waitForAnimation(_ duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    // MARK: - MCP Tool Wrappers (placeholders for actual MCP calls)

    private func tap(at point: CGPoint) async throws {
        // In real implementation:
        // await mcp.tap(simulatorUuid: simulatorUuid, x: Int(point.x), y: Int(point.y))
        throw MCPError.notImplemented("MCP tap not yet integrated")
    }

    func type(text: String) async throws {
        // In real implementation:
        // await mcp.type_text(simulatorUuid: simulatorUuid, text: text)
        throw MCPError.notImplemented("MCP type_text not yet integrated")
    }

    func screenshot(name: String) async throws {
        // In real implementation:
        // let image = await mcp.screenshot(simulatorUuid: simulatorUuid)
        // save to test artifacts
        throw MCPError.notImplemented("MCP screenshot not yet integrated")
    }

    func swipe(from: CGPoint, to: CGPoint, duration: TimeInterval = 0.3) async throws {
        // In real implementation:
        // await mcp.swipe(simulatorUuid: simulatorUuid, x1: from.x, y1: from.y, x2: to.x, y2: to.y, duration: duration)
        throw MCPError.notImplemented("MCP swipe not yet integrated")
    }

    // MARK: - High-Level Workflows

    /// Navigate to a specific view by tapping through navigation hierarchy
    func navigateTo(_ destination: String, from path: [String] = []) async throws {
        for step in path {
            try await tapButton(step)
            try await waitForAnimation(0.5)
        }

        // Verify we arrived
        let ui = try await describeUI()
        guard ui.hasText(destination) else {
            throw MCPError.navigationFailed("Failed to navigate to '\(destination)'")
        }
    }

    /// Fill text field
    func fillTextField(label: String, text: String) async throws {
        guard let textField = try await findTextField(label) else {
            throw MCPError.elementNotFound("TextField with label '\(label)' not found")
        }

        try await tap(at: textField.center) // Focus
        try await waitForAnimation(0.2)
        try await self.type(text: text)
    }

    /// Verify element exists
    func verifyElementExists(label: String) async throws {
        let ui = try await describeUI()
        guard ui.findElement(label: label) != nil else {
            throw MCPError.assertionFailed("Expected element '\(label)' to exist")
        }
    }

    /// Verify text appears somewhere in UI
    func verifyTextAppears(_ text: String) async throws {
        let ui = try await describeUI()
        guard ui.hasText(text) else {
            throw MCPError.assertionFailed("Expected text '\(text)' to appear in UI")
        }
    }
}

// MARK: - Errors

enum MCPError: Error, LocalizedError {
    case notImplemented(String)
    case elementNotFound(String)
    case timeout(String)
    case navigationFailed(String)
    case assertionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let msg),
             .elementNotFound(let msg),
             .timeout(let msg),
             .navigationFailed(let msg),
             .assertionFailed(let msg):
            return msg
        }
    }
}

// MARK: - Test Usage Example

@available(macOS 13.0, iOS 16.0, *)
extension MCPUIAutomationHelper {
    /// Example: Recording flow test
    func exampleRecordingFlowTest() async throws {
        // Self-healing - no hardcoded coordinates
        try await tapButton("Gravar") // pt-BR
        try await waitForElement(label: "Pausar", timeout: 2.0)
        try await screenshot(name: "recording_active")

        try await Task.sleep(nanoseconds: 10_000_000_000) // 10s

        try await tapButton("Parar")
        try await waitForElement(label: "Transcript", timeout: 5.0)
        try await verifyTextAppears("Synthetic")
        try await screenshot(name: "transcript_visible")
    }

    /// Example: Speaker enrollment flow
    func exampleSpeakerEnrollmentTest() async throws {
        try await navigateTo("Falantes", from: ["Configurações"])
        try await tapButton("Inscrever Falante")

        try await fillTextField(label: "Nome", text: "Falante Teste")
        try await tapButton("Iniciar Gravação")

        try await Task.sleep(nanoseconds: 8_500_000_000) // 8.5s

        try await tapButton("Salvar")
        try await waitForAnimation(1.0)
        try await verifyTextAppears("Falante Teste")
    }
}
