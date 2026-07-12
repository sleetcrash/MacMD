import SwiftUI

/// Built-in starting points for the agent-config documents MacMD is most used
/// for. Each opens as a fresh Untitled document; nothing is written to disk
/// until the user saves.
enum DocumentTemplate: String, CaseIterable, Identifiable {
    case skill, agent, claudeMd, agentsMd

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .skill: return "Skill (SKILL.md)"
        case .agent: return "Agent (agent-name.md)"
        case .claudeMd: return "CLAUDE.md"
        case .agentsMd: return "AGENTS.md"
        }
    }

    var text: String {
        switch self {
        case .skill:
            return """
            ---
            name: skill-name
            description: What this skill does and when to use it. Write the trigger phrases a user would actually type; the model matches on this text.
            ---

            # Skill Name

            ## When to use

            - Use when: ...
            - Do NOT use for: ... (name the sibling skill that owns it)

            ## Instructions

            1. First step.
            2. Second step.

            ## Bundled resources

            - `scripts/` helper scripts run as-is
            - `references/` deep-dive docs, loaded only when needed
            """
        case .agent:
            return """
            ---
            name: agent-name
            description: When to dispatch this agent. Include 2-3 concrete trigger scenarios; the harness matches on this text. State what it must NOT be used for.
            tools: Read, Grep, Glob, Bash
            ---

            You are agent-name, a focused subagent with one job.

            ## Role

            State the single responsibility.

            ## Process

            1. Gather context.
            2. Do the work.
            3. Verify the result.

            ## Output

            Report findings as: ...
            """
        case .claudeMd:
            return """
            # Project Name

            One-line description of what this project is.

            ## Commands

            - Build: `...`
            - Test: `...`
            - Run: `...`

            ## Architecture

            - Entry point: ...
            - Key modules: ...

            ## Conventions

            - Code style: ...
            - Commit style: ...

            ## Boundaries

            - Never touch: ...
            - Always ask before: ...
            """
        case .agentsMd:
            return """
            # AGENTS.md

            Guidance for AI coding agents working in this repository.

            ## Setup

            - Install: `...`

            ## Commands

            - Build: `...`
            - Test: `...`
            - Lint: `...`

            ## Code style

            - ...

            ## Boundaries

            - Never commit directly to main.
            - Never touch: ...
            """
        }
    }
}

/// File > New from Template: opens a new Untitled document pre-filled with the
/// chosen template.
struct TemplateCommands: Commands {
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("New from Template") {
                ForEach(DocumentTemplate.allCases) { template in
                    Button(template.menuTitle) {
                        newDocument(MarkdownDocument(text: template.text))
                    }
                }
            }
        }
    }
}
