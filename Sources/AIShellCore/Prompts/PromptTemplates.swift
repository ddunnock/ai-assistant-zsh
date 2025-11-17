// Sources/AIShellCore/Prompts/PromptTemplates.swift

import Foundation

/// Prompt template manager
public actor PromptTemplates {
    private var templates: [String: PromptTemplate]
    private let storageURL: URL?
    private let logger = LoggerFactory.create(category: "prompts")

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        self.templates = Self.defaultTemplates()
    }

    // MARK: - Template Access

    /// Get a template by name
    public func getTemplate(_ name: String) -> PromptTemplate? {
        return templates[name]
    }

    /// Set or update a template
    public func setTemplate(_ name: String, template: PromptTemplate) {
        templates[name] = template
        logger.debug("Updated template", metadata: ["name": name])
    }

    /// Build a prompt from template
    public func buildPrompt(
        templateName: String,
        variables: [String: String]
    ) -> String? {
        guard let template = templates[templateName] else {
            logger.warning("Template not found", metadata: ["name": templateName])
            return nil
        }

        return template.render(variables: variables)
    }

    // MARK: - Persistence

    /// Load templates from disk
    public func load() async throws {
        guard let storageURL = storageURL else { return }
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            logger.info("No existing templates found, using defaults")
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()

        let loaded = try decoder.decode([String: PromptTemplate].self, from: data)
        templates = loaded

        logger.info("Loaded templates from disk", metadata: [
            "path": storageURL.path,
            "count": String(templates.count)
        ])
    }

    /// Save templates to disk
    public func save() async throws {
        guard let storageURL = storageURL else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let encoded = try encoder.encode(templates)

        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try encoded.write(to: storageURL)

        logger.info("Saved templates to disk", metadata: [
            "path": storageURL.path
        ])
    }

    // MARK: - Default Templates

    private static func defaultTemplates() -> [String: PromptTemplate] {
        return [
            "suggest_system": PromptTemplate(
                system: "You are a shell command assistant. Suggest completions or improvements for shell commands. Be concise and output only the suggested command without explanation.",
                user: nil
            ),

            "suggest_user": PromptTemplate(
                system: nil,
                user: """
                Current command: {{command}}
                {{#if history}}
                Recent commands:
                {{#each history}}
                - {{this}}
                {{/each}}
                {{/if}}
                {{#if gitBranch}}
                Git branch: {{gitBranch}}
                {{/if}}
                {{#if workingDirectory}}
                Working directory: {{workingDirectory}}
                {{/if}}
                {{#if relevantContext}}
                Relevant context:
                {{relevantContext}}
                {{/if}}

                Suggest an improvement or completion for the current command.
                """
            ),

            "explain_system": PromptTemplate(
                system: "You are a shell command expert. Explain commands clearly and accurately.",
                user: nil
            ),

            "explain_user": PromptTemplate(
                system: nil,
                user: """
                Explain this shell command in clear, concise language:

                Command: {{command}}

                Provide:
                1. What the command does
                2. What each option/flag means
                3. Any potential risks or side effects

                Keep the explanation under 200 words.
                """
            ),

            "task_system": PromptTemplate(
                system: "You are a shell scripting expert. Convert tasks to safe, efficient shell commands.",
                user: nil
            ),

            "task_user": PromptTemplate(
                system: nil,
                user: """
                Convert this natural language task into shell commands:

                Task: {{task}}
                Working Directory: {{workingDirectory}}
                {{#if relevantContext}}
                Relevant context:
                {{relevantContext}}
                {{/if}}
                {{#if conversationHistory}}
                Recent conversation:
                {{conversationHistory}}
                {{/if}}

                Output only the commands, one per line, with no explanation or markdown.
                """
            ),

            "conversation_system": PromptTemplate(
                system: """
                You are an AI shell assistant. Help users with command-line tasks.
                You have access to conversation history and can remember context.
                Be concise but friendly. Provide executable commands when appropriate.
                """,
                user: nil
            )
        ]
    }
}

/// A prompt template
public struct PromptTemplate: Codable {
    public let system: String?
    public let user: String?

    public init(system: String?, user: String?) {
        self.system = system
        self.user = user
    }

    /// Render template with variables
    public func render(variables: [String: String]) -> String {
        var result = user ?? ""

        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        // Simple conditional handling for {{#if key}} ... {{/if}}
        result = processConditionals(result, variables: variables)

        // Simple iteration handling for {{#each key}} ... {{/each}}
        result = processIterations(result, variables: variables)

        return result
    }

    private func processConditionals(_ template: String, variables: [String: String]) -> String {
        var result = template
        let pattern = #"\{\{#if\s+(\w+)\}\}(.*?)\{\{/if\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return result
        }

        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))

        for match in matches.reversed() {
            guard let conditionRange = Range(match.range(at: 1), in: template),
                  let contentRange = Range(match.range(at: 2), in: template),
                  let fullRange = Range(match.range, in: template) else {
                continue
            }

            let condition = String(template[conditionRange])
            let content = String(template[contentRange])

            // Replace with content if variable exists and is non-empty
            if let value = variables[condition], !value.isEmpty {
                result.replaceSubrange(fullRange, with: content)
            } else {
                result.replaceSubrange(fullRange, with: "")
            }
        }

        return result
    }

    private func processIterations(_ template: String, variables: [String: String]) -> String {
        var result = template
        let pattern = #"\{\{#each\s+(\w+)\}\}(.*?)\{\{/each\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return result
        }

        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))

        for match in matches.reversed() {
            guard let arrayNameRange = Range(match.range(at: 1), in: template),
                  let itemTemplateRange = Range(match.range(at: 2), in: template),
                  let fullRange = Range(match.range, in: template) else {
                continue
            }

            let arrayName = String(template[arrayNameRange])
            let itemTemplate = String(template[itemTemplateRange])

            // Try to get array as JSON
            if let arrayJSON = variables[arrayName],
               let data = arrayJSON.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: data) as? [String] {

                let rendered = items.map { item in
                    itemTemplate.replacingOccurrences(of: "{{this}}", with: item)
                }.joined()

                result.replaceSubrange(fullRange, with: rendered)
            } else {
                result.replaceSubrange(fullRange, with: "")
            }
        }

        return result
    }
}
