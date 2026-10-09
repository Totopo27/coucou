import Foundation

/// Where an imported MCP server configuration was found on this Mac.
enum MCPServerSource: String, Codable, Equatable, Sendable, CaseIterable {
    case claudeDesktop = "claude-desktop"
    case claudeCode    = "claude-code"
    case cursor        = "cursor"
    case vscode        = "vscode"
    case windsurf      = "windsurf"
    case opencode      = "opencode"
    case manual        = "manual"

    var displayName: String {
        switch self {
        case .claudeDesktop: return "Claude Desktop"
        case .claudeCode:    return "Claude Code"
        case .cursor:        return "Cursor"
        case .vscode:        return "VS Code"
        case .windsurf:      return "Windsurf"
        case .opencode:      return "OpenCode"
        case .manual:        return "Manual"
        }
    }
}

/// Transport protocol used to communicate with an MCP server.
enum MCPTransport: Codable, Equatable, Sendable {
    case stdio(command: String, args: [String], env: [String: String])
    case http(url: String, headers: [String: String])

    private enum CodingKeys: String, CodingKey {
        case type, command, args, env, url, headers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "stdio" {
            let command = try container.decode(String.self, forKey: .command)
            let args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
            let env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
            self = .stdio(command: command, args: args, env: env)
        } else if type == "http" {
            let url = try container.decode(String.self, forKey: .url)
            let headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
            self = .http(url: url, headers: headers)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown MCP transport: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stdio(let command, let args, let env):
            try container.encode("stdio", forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(args, forKey: .args)
            try container.encode(env, forKey: .env)
        case .http(let url, let headers):
            try container.encode("http", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(headers, forKey: .headers)
        }
    }
}

/// A configured MCP server discovered or added in Coucou.
struct MCPServerConfig: Codable, Identifiable, Equatable, Sendable {
    /// Stable unique slug (e.g. "postgres", "github-2").
    let id: String
    /// Human-friendly display name.
    var name: String
    /// Developer tools where this server was discovered.
    var sources: [MCPServerSource]
    /// How Coucou communicates with this server (subprocess stdio or remote HTTP).
    var transport: MCPTransport
    /// Whether this server is active and exposed to the chat.
    var isEnabled: Bool
    /// If true, only read-only tools can run automatically; mutating tools ask in the Island.
    var isReadOnly: Bool
    /// Informational notes (e.g. environment variable requirements, warnings).
    var notes: [String]

    init(id: String,
         name: String,
         sources: [MCPServerSource],
         transport: MCPTransport,
         isEnabled: Bool = true,
         isReadOnly: Bool = true,
         notes: [String] = []) {
        self.id = id
        self.name = name
        self.sources = sources
        self.transport = transport
        self.isEnabled = isEnabled
        self.isReadOnly = isReadOnly
        self.notes = notes
    }

    /// Short human-readable summary for settings lists (with credentials masked).
    var summary: String {
        switch transport {
        case .stdio(let command, let args, _):
            let shortCommand = (command as NSString).lastPathComponent
            let visibleArgs = args.prefix(3).map { MCPScanner.maskPotentialSecret($0) }
            return ([shortCommand] + visibleArgs).joined(separator: " ")
        case .http(let url, _):
            return MCPScanner.maskURL(url)
        }
    }
}
