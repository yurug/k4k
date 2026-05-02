# OpenCode Codebase Report

Date: 2026-05-02

## Executive Summary

OpenCode is best understood as an open, provider-agnostic AI coding agent platform rather than only a terminal chat client. The README's core claim is simple, "The open source AI coding agent," and the implementation backs that up with a full CLI, TUI-oriented server, OpenAPI surface, SDK generation, web app, desktop shells, plugin system, MCP integration, agent registry, permissions, snapshots, and language-server feedback loops ([README](../opencode/README.md#L10), [server docs](../opencode/packages/web/src/content/docs/server.mdx#L47)).

The strongest value proposition is control. Users can pick models and providers, inspect the code, run the system locally, extend it with plugins and MCP servers, and drive it through HTTP clients rather than being locked into a single hosted agent product ([providers docs](../opencode/packages/web/src/content/docs/providers.mdx#L9), [server docs](../opencode/packages/web/src/content/docs/server.mdx#L72)).

The largest weakness is also control. OpenCode exposes a very powerful local automation surface, and much of it is permissive by default: the build agent has broad tool access, server authentication is optional, plugins can execute local code, npm plugin dependencies can be installed automatically, MCP servers become model tools, and the permission model depends heavily on wildcard patterns and individual tools correctly declaring what they are about to do. That is a reasonable local-developer tradeoff, but it is not a conservative security posture.

## Value Proposition

### Open Source Agent Control

OpenCode positions itself directly against closed-source coding agents. Its FAQ highlights that it is "100% open source," not subscription-bound, and not tied to one model provider ([README](../opencode/README.md#L129)). This matters because coding agents sit on sensitive local context: source code, shell access, credentials, terminals, git state, editor state, and potentially company-private repositories. An inspectable implementation is a real product advantage for developers and organizations that will not trust opaque automation around those assets.

### Provider And Model Choice

The provider layer is a major differentiator. The documentation claims support for 75+ providers through AI SDK and Models.dev, including local models ([providers docs](../opencode/packages/web/src/content/docs/providers.mdx#L9)). The implementation imports and adapts many provider SDKs, including Anthropic, OpenAI, Google, Bedrock, Azure, GitHub Copilot, xAI, Groq, Cerebras, Mistral, Vercel, Cloudflare, and local-compatible APIs ([provider.ts](../opencode/packages/opencode/src/provider/provider.ts#L92)).

This gives OpenCode a strong "bring your own model" story. It lets users optimize for price, quality, latency, privacy, quota, policy, or local execution. It also helps the project survive model-market churn because the user-facing product is not coupled to one vendor.

### Terminal First, But Not Terminal Only

OpenCode keeps the terminal as the primary surface, but the architecture is broader than a terminal app. The server docs state that when OpenCode runs it starts both the TUI and a server, and that the TUI is a client of that server ([server docs](../opencode/packages/web/src/content/docs/server.mdx#L47)). The server exposes OpenAPI, supports multiple clients, can be run headlessly, and has a `/tui` endpoint used by IDE plugins ([server docs](../opencode/packages/web/src/content/docs/server.mdx#L53), [server docs](../opencode/packages/web/src/content/docs/server.mdx#L64)).

That design lets OpenCode support terminal workflows, web clients, desktop clients, IDE integrations, SDK automation, and programmatic use from one core. The monorepo structure reinforces this: `packages/opencode` contains the agent/server core, while `packages/app`, `packages/desktop`, `packages/ui`, `sdk/js`, and console packages build user-facing or integration surfaces around it.

### Extensible Automation Platform

OpenCode's value is not just built-in agent behavior. Users can configure agents, commands, plugins, MCP servers, LSP servers, custom tools, permissions, and provider settings. Agents are first-class, with primary agents for direct conversation and subagents for delegated tasks ([agents docs](../opencode/packages/web/src/content/docs/agents.mdx#L18)). MCP servers expose external tools to the LLM ([MCP docs](../opencode/packages/web/src/content/docs/mcp-servers.mdx#L6)). Plugins can hook events and customize behavior ([plugin docs](../opencode/packages/web/src/content/docs/plugins.mdx#L6)).

This makes OpenCode more like a programmable agent runtime than a fixed CLI. That is valuable for power users and teams, especially where coding-agent behavior needs to be integrated into existing developer environments.

### Developer-Grade Feedback Loops

The project invests in concrete developer feedback: language-server diagnostics, diff-aware edit permissions, snapshots, session parts, cost and token tracking, and event replay. LSP integration is documented as a way to give diagnostics to the LLM ([LSP docs](../opencode/packages/web/src/content/docs/lsp.mdx#L6)). Write and edit tools return diagnostics after file changes ([write tool](../opencode/packages/opencode/src/tool/write.ts#L64), [edit tool](../opencode/packages/opencode/src/tool/edit.ts#L88)). The session processor records snapshots, patches, tokens, cost, and completion state during the model/tool loop ([processor.ts](../opencode/packages/opencode/src/session/processor.ts#L346)).

That is an important value proposition: OpenCode is built around real code-editing loops, not generic chat completions.

## Core Principles

### 1. User Choice Over Vendor Lock-In

The system consistently favors pluggability: many providers, local models, MCP, plugins, custom tools, configurable agents, and layered configuration. This is visible in the provider implementation, MCP client, plugin loader, and config schema ([provider.ts](../opencode/packages/opencode/src/provider/provider.ts#L141), [mcp/index.ts](../opencode/packages/opencode/src/mcp/index.ts#L420), [tool registry](../opencode/packages/opencode/src/tool/registry.ts#L161), [config.ts](../opencode/packages/opencode/src/config/config.ts#L102)).

The principle is sound: the coding agent should be an interface over interchangeable capabilities, not a single hard-coded model workflow.

### 2. Client/Server Separation As A Product Primitive

OpenCode's TUI is not a special-case implementation buried inside the model loop. It talks to a server that also serves HTTP clients, OpenAPI docs, SDKs, IDE plugins, and web/desktop frontends ([server docs](../opencode/packages/web/src/content/docs/server.mdx#L47)). The server routes are organized around workspaces and instances, and the server generates OpenAPI specs programmatically ([server.ts](../opencode/packages/opencode/src/server/server.ts#L111), [server.ts](../opencode/packages/opencode/src/server/server.ts#L138)).

This is a strong architectural principle because it prevents the TUI from becoming the only integration point.

### 3. Tool-First Agency

OpenCode models agent capability through tools. The tool contract uses schemas, structured execution, telemetry spans, and truncation behavior ([tool.ts](../opencode/packages/opencode/src/tool/tool.ts#L1)). The registry assembles built-in tools, custom tool files, plugin tools, MCP tools, model-specific substitutions, and permission-filtered task agents ([registry.ts](../opencode/packages/opencode/src/tool/registry.ts#L187)).

This creates a clear boundary between language-model reasoning and side effects. The model can request actions, but concrete code decides how those actions are validated, permissioned, executed, reported, and logged.

### 4. Permissioned Autonomy

The permission model is designed to let users trade speed against control. Actions can be allowed, asked, or denied; rules are pattern-based; and the last matching rule wins ([permissions docs](../opencode/packages/web/src/content/docs/permissions.mdx#L14), [evaluate.ts](../opencode/packages/opencode/src/permission/evaluate.ts#L9)). The runtime asks the user for pending permissions and supports "always" approvals for the current session ([permission index](../opencode/packages/opencode/src/permission/index.ts#L180), [permission index](../opencode/packages/opencode/src/permission/index.ts#L217)).

The principle is good: an agent should not need a full stop for every action, but users need hooks to stop dangerous behavior.

### 5. Extensibility Is A First-Class Surface

Plugins, MCP servers, custom tools, skills, commands, custom agents, and LSP configuration are not afterthoughts. They are deeply wired into the config loader, tool registry, session processor, and model call path. Plugin hooks can mutate prompts, tool definitions, shell environments, chat parameters, headers, and generated text ([llm.ts](../opencode/packages/opencode/src/session/llm.ts#L103), [bash.ts](../opencode/packages/opencode/src/tool/bash.ts#L404), [registry.ts](../opencode/packages/opencode/src/tool/registry.ts#L275)).

This is a deliberate platform bet. It makes OpenCode adaptable, but it also makes the effective runtime behavior much harder to reason about.

### 6. Pragmatism Over Purity

The provider and tool layers contain many compatibility branches. For example, OpenAI OAuth uses a different instruction path, LiteLLM/GitHub Copilot compatibility can require a no-op tool, and some providers require custom tool execution or headers ([llm.ts](../opencode/packages/opencode/src/session/llm.ts#L130), [llm.ts](../opencode/packages/opencode/src/session/llm.ts#L195), [provider.ts](../opencode/packages/opencode/src/provider/provider.ts#L141)).

This is pragmatic engineering. OpenCode chooses to support the messy model ecosystem rather than expose a pure abstraction that works only for ideal providers.

### 7. Durable Local State And Replayable Events

The core uses SQLite with WAL mode, migrations, typed events, sequence checks, projectors, and a bus that carries workspace/project context ([db.ts](../opencode/packages/opencode/src/storage/db.ts#L91), [sync/index.ts](../opencode/packages/opencode/src/sync/index.ts#L23), [bus/index.ts](../opencode/packages/opencode/src/bus/index.ts#L30)). This gives the product a durable session model and a foundation for multi-client UI updates.

The principle is that agent sessions are not ephemeral text streams. They are application state.

## Key Architectural And Design Choices

### Monorepo With A Large TypeScript Core

The core implementation lives in `packages/opencode`, with surrounding packages for web UI, desktop, console, shared UI components, SDK generation, enterprise integrations, and scripts. The package is TypeScript-first, Bun-oriented, and uses Effect for dependency layers and runtime composition. The root package explicitly tells contributors not to run tests from the monorepo root, while package-local scripts own build, typecheck, and test behavior.

This structure supports multiple product surfaces from a shared agent runtime, but it also raises coordination cost: changes to config, server contracts, events, or tool semantics can affect many packages.

### CLI As The Entry Point Into A Server-Centered Runtime

The CLI entry point wires many commands through yargs: `run`, `serve`, `web`, `models`, `providers`, `agent`, `mcp`, `github`, `session`, `plugin`, database tools, generation tools, and more ([index.ts](../opencode/packages/opencode/src/index.ts#L1)). The middleware initializes environment markers, logging, telemetry helpers, and one-time database migration state before command execution.

The CLI is therefore not only a command runner. It is the user's front door into a local agent platform.

### Stable Hono Server Plus Experimental Effect HTTP API Backend

The server currently supports two backends: Hono as the stable default and an experimental Effect HTTP API backend selected by config or environment ([backend.ts](../opencode/packages/opencode/src/server/backend.ts#L4), [server.ts](../opencode/packages/opencode/src/server/server.ts#L49)). The Hono server applies error, auth, logger, compression, CORS, and route middleware, then exposes workspace and instance routes ([server.ts](../opencode/packages/opencode/src/server/server.ts#L99)). The experimental backend has its own assembled route layer and many service dependencies ([httpapi server](../opencode/packages/opencode/src/server/routes/instance/httpapi/server.ts#L95)).

This is a sensible migration strategy, but it creates a dual-stack risk. The existence of JSON parity tests is encouraging, but also evidence that API behavior can drift unless actively policed ([httpapi parity test](../opencode/packages/opencode/test/server/httpapi-json-parity.test.ts#L96)).

### OpenAPI And SDK Generation

The server generates OpenAPI specs and the docs expose `/doc` as the OpenAPI endpoint ([server.ts](../opencode/packages/opencode/src/server/server.ts#L138), [server docs](../opencode/packages/web/src/content/docs/server.mdx#L72)). The JavaScript SDK package exports generated clients. This is the right choice for a client/server architecture because it makes external clients and internal UI surfaces share a contract rather than duplicate route knowledge.

The weakness is that contract correctness depends on validators, route behavior, generated SDKs, and documentation all staying in sync.

### Agent Registry With Primary, Subagent, And Hidden Agents

OpenCode defines built-in agents for build, plan, general, explore, compaction, title, and summary tasks, with user config able to override or create agents ([agent.ts](../opencode/packages/opencode/src/agent/agent.ts#L111), [agent.ts](../opencode/packages/opencode/src/agent/agent.ts#L238)). Agent definitions include mode, description, prompt, model, tool permissions, options, and step limits ([agent.ts](../opencode/packages/opencode/src/agent/agent.ts#L28)).

This is a strong design because it avoids forcing one agent persona and one tool policy onto every task. It also gives the task tool a natural way to route work to specialized subagents.

### Session Processor As The Model/Tool Orchestrator

The session processor owns the live loop: build context, call the LLM, handle tool calls, publish session parts, record snapshots, capture cost and token data, run compaction when context overflows, and detect repeated tool calls as possible doom loops ([processor.ts](../opencode/packages/opencode/src/session/processor.ts#L108), [processor.ts](../opencode/packages/opencode/src/session/processor.ts#L300), [processor.ts](../opencode/packages/opencode/src/session/processor.ts#L346)).

This is a necessary concentration of complexity. It is also one of the most important files in the system because bugs here affect correctness, safety, UI state, billing visibility, and recovery behavior.

### Tool Registry With Built-Ins, Plugins, Custom Files, MCP, And Model-Specific Choices

The registry builds a model-visible tool list from multiple sources: built-ins, plugin-defined tools, custom `tool` directories, MCP tools, optional LSP tools, and plan-specific tools ([registry.ts](../opencode/packages/opencode/src/tool/registry.ts#L122), [registry.ts](../opencode/packages/opencode/src/tool/registry.ts#L161), [registry.ts](../opencode/packages/opencode/src/tool/registry.ts#L187)). It also changes available tools by provider or model, for example preferring `apply_patch` for some GPT models and gating web search to supported providers ([registry.ts](../opencode/packages/opencode/src/tool/registry.ts#L275)).

This is a powerful abstraction, but it means the tool surface is dynamic. Debugging "what was the model allowed to do?" requires knowing agent config, model, provider, user tool filters, plugin hooks, MCP state, and permission rules.

### Permission Model: Flat Wildcards, Last Match Wins

Permissions use a flat rule list evaluated with wildcard matching, and the last matching rule wins ([evaluate.ts](../opencode/packages/opencode/src/permission/evaluate.ts#L9)). Tools ask permissions by declaring permission IDs, path or command patterns, and optional metadata such as diffs ([permission index](../opencode/packages/opencode/src/permission/index.ts#L180)). External-directory access is handled by a separate helper that asks when a path escapes the project directory ([external-directory.ts](../opencode/packages/opencode/src/tool/external-directory.ts#L16)).

The design is simple and flexible. Its weakness is auditability: with enough config layers, plugin tools, MCP tools, and generated patterns, it becomes difficult for a user to know what a rule actually permits.

### Diff-Aware File Editing

The edit, write, and apply-patch tools resolve paths, check external-directory boundaries, generate diffs, ask edit permission with diff metadata, write files, publish file events, format files, and report LSP diagnostics ([edit.ts](../opencode/packages/opencode/src/tool/edit.ts#L79), [write.ts](../opencode/packages/opencode/src/tool/write.ts#L53), [apply_patch.ts](../opencode/packages/opencode/src/tool/apply_patch.ts#L200)).

This is the right shape for code editing because it exposes proposed changes before mutation. It is not a full transactional editing system, though, and that matters in the weaknesses below.

### MCP And Plugin Systems As Capability Multipliers

MCP tools are converted into AI SDK dynamic tools and executed through local or remote MCP clients ([mcp/index.ts](../opencode/packages/opencode/src/mcp/index.ts#L122)). Remote MCP supports OAuth and streamable HTTP/SSE transports, while local MCP runs configured commands under the project directory ([mcp/index.ts](../opencode/packages/opencode/src/mcp/index.ts#L269), [mcp/index.ts](../opencode/packages/opencode/src/mcp/index.ts#L385)). Plugins can be local, global, or npm-backed; npm plugins are installed and cached through Bun ([plugin docs](../opencode/packages/web/src/content/docs/plugins.mdx#L18), [plugin docs](../opencode/packages/web/src/content/docs/plugins.mdx#L46)).

This is one of OpenCode's biggest advantages for advanced users. It is also one of its largest trust-boundary risks.

### Layered Configuration And Managed Environments

Configuration is JSON/JSONC, merged rather than replaced, and loaded from remote org defaults, global config, custom config, project config, `.opencode` directories, inline environment content, managed files, and MDM preferences ([config docs](../opencode/packages/web/src/content/docs/config.mdx#L12), [config docs](../opencode/packages/web/src/content/docs/config.mdx#L32), [config docs](../opencode/packages/web/src/content/docs/config.mdx#L42)). The loader fetches remote `.well-known/opencode` config and merges it into global config when auth entries provide that path ([config.ts](../opencode/packages/opencode/src/config/config.ts#L492)).

This is valuable for teams and enterprises. It also creates a lot of implicit behavior, especially because config can affect agents, permissions, MCP servers, plugins, LSP, providers, and tools.

## Weaknesses And Risks

### 1. The Security Posture Is Powerful But Permissive

OpenCode is designed for local trusted developer workflows, not as a conservative sandbox. The default agent permissions start with broad allow rules, including `*` allow and read allow, with special handling for `.env` and external directories ([agent.ts](../opencode/packages/opencode/src/agent/agent.ts#L90)). The README says the default build agent has access to all tools ([README](../opencode/README.md#L100)).

That is productive, but it is risky. A model, plugin, MCP server, or compromised repo can attempt broad side effects unless the user has tightened permissions. OpenCode has controls, but users must understand and use them.

### 2. Server Authentication Is Optional

The server auth middleware allows requests through when no password is configured ([middleware.ts](../opencode/packages/opencode/src/server/middleware.ts#L41)). The `serve` command warns when `OPENCODE_SERVER_PASSWORD` is unset, but still starts the server ([serve.ts](../opencode/packages/opencode/src/cli/cmd/serve.ts#L10)). CORS allows localhost, Tauri/renderer origins, explicit configured origins, and `*.opencode.ai` origins ([cors.ts](../opencode/packages/opencode/src/server/cors.ts#L5)).

This is acceptable for loopback-only local use. It becomes dangerous if the server is bound to a reachable interface, tunneled, proxied, or launched in a shared environment. The API surface can drive sessions, tools, PTYs, files within the workspace, providers, config, and TUI behavior. The default should probably make the unsafe deployment mode harder to enter.

### 3. Public Docs Appear To Diverge From Source On Plan Agent Safety

The docs describe the plan agent as unable to make edits and as requiring permission for bash commands ([README](../opencode/README.md#L104), [agents docs](../opencode/packages/web/src/content/docs/agents.mdx#L58)). The source denies edits for most files in the plan agent, but it inherits the default permission set, whose first rule is `* allow`; I did not see a built-in `bash` ask rule in the plan agent definition ([agent.ts](../opencode/packages/opencode/src/agent/agent.ts#L90), [agent.ts](../opencode/packages/opencode/src/agent/agent.ts#L127)).

Unless another layer rewrites this at runtime, the documentation overstates the built-in bash restriction. That is a significant issue because users may choose plan mode expecting safer behavior.

### 4. Public Docs Appear To Diverge From Source On `.env` Reads

The permissions docs say `.env` files are denied by default ([permissions docs](../opencode/packages/web/src/content/docs/permissions.mdx#L148)). The source default permission for `.env` and `.env.*` is `ask`, while `.env.example` is explicitly allowed ([agent.ts](../opencode/packages/opencode/src/agent/agent.ts#L101)).

`ask` is not the same as `deny`. The source behavior may be better for usability, but the mismatch is harmful because secrets handling is exactly where users need precise expectations.

### 5. Pattern-Based Permissions Are Easy To Misread

The permission evaluator is intentionally small: find the last matching wildcard rule and return its action ([evaluate.ts](../opencode/packages/opencode/src/permission/evaluate.ts#L9)). That simplicity is attractive, but patterns are only as good as the tool-provided target strings. Bash tries to parse commands with tree-sitter, identify command prefixes and path arguments, and generate `always` patterns such as prefix plus wildcard ([bash.ts](../opencode/packages/opencode/src/tool/bash.ts#L30), [bash.ts](../opencode/packages/opencode/src/tool/bash.ts#L367)).

Shell semantics are too large to model perfectly. Aliases, wrappers, environment-dependent commands, scripts, generated paths, subshells, and provider/plugin-injected environment changes can make a user-approved pattern broader than expected. The model is usable, but it should not be mistaken for a sandbox.

### 6. Plugin And MCP Execution Create A Large Supply-Chain Surface

Plugins are auto-loaded from local and global plugin directories, npm plugins can be auto-installed and cached, local plugin dependencies can run `bun install`, and plugin code can hook sensitive paths such as prompts, chat parameters, tool definitions, shell environment, and generated text ([plugin docs](../opencode/packages/web/src/content/docs/plugins.mdx#L18), [plugin docs](../opencode/packages/web/src/content/docs/plugins.mdx#L46), [plugin docs](../opencode/packages/web/src/content/docs/plugins.mdx#L74), [llm.ts](../opencode/packages/opencode/src/session/llm.ts#L161)). Local MCP servers run arbitrary configured commands, and remote MCP servers can provide additional tools to the model ([mcp/index.ts](../opencode/packages/opencode/src/mcp/index.ts#L385), [mcp/index.ts](../opencode/packages/opencode/src/mcp/index.ts#L122)).

This is the right extension model for power users, but it turns repo and config trust into code-execution trust. A strict enterprise deployment would need strong controls around plugin sources, MCP sources, auto-install behavior, and project-local config.

### 7. The Client API Is Not The Same Boundary As LLM Tool Permissions

The file API has path containment checks, for example reads are joined to the instance directory and denied when outside it ([file/index.ts](../opencode/packages/opencode/src/file/index.ts#L505)). That is good. But the server is a client API for controlling OpenCode, not just a proxy around LLM tools. It exposes broad application functionality, and those client routes do not all mean "ask the model permission first." That is normal for a local app server, but it reinforces why optional auth and network exposure are risky.

The practical rule is: the OpenCode server should be treated like a privileged local control plane.

### 8. Dual Server Backends Add Migration Risk

Maintaining Hono and experimental Effect HTTP API backends creates duplicate semantics, not just duplicate code. The project has parity tests, but the experimental route layer wires a large set of services independently from the Hono path ([httpapi server](../opencode/packages/opencode/src/server/routes/instance/httpapi/server.ts#L140)). Every route, serialization choice, error shape, auth behavior, event stream, and edge case can drift.

This may be a necessary migration, but it is architectural debt until one backend clearly wins.

### 9. Provider Breadth Causes Behavioral Drift

Provider support is a product strength, but the code already contains many provider-specific branches: headers, options, OAuth behavior, response-mode choices, tool compatibility shims, custom model filtering, and special tool executors ([provider.ts](../opencode/packages/opencode/src/provider/provider.ts#L141), [llm.ts](../opencode/packages/opencode/src/session/llm.ts#L195)). That makes it hard to promise identical agent behavior across providers.

The likely failure mode is not total breakage. It is subtle: a tool is hidden for one model, tool choice works differently, system prompts are sent through a different field, streaming parts arrive in a different shape, or cost/context handling differs.

### 10. Editing Safety Is Good, But Not Transactional

The edit path uses file-level locks inside the OpenCode process, generates a diff, asks permission, writes, formats, and emits diagnostics ([edit.ts](../opencode/packages/opencode/src/tool/edit.ts#L35), [edit.ts](../opencode/packages/opencode/src/tool/edit.ts#L88)). That is solid baseline safety.

The weakness is that I do not see an explicit read-before-edit freshness contract or compare-and-swap check against external changes between diff approval and write. If the user or another process changes the file during that window, OpenCode can still write based on stale assumptions. For a coding agent, stale edits are a high-impact class of bug because they can silently discard or distort nearby work.

### 11. Config Precedence Is Powerful, But Hard To Predict

Config is merged from many sources and arrays such as instructions have custom merge behavior ([config.ts](../opencode/packages/opencode/src/config/config.ts#L49)). Config sources include remote org defaults, global user files, project files, `.opencode` directories, inline environment content, managed files, and MDM preferences ([config docs](../opencode/packages/web/src/content/docs/config.mdx#L42)). That is useful for real deployments, but it also makes it hard to answer "why did the agent do this?" without tooling that explains the final effective config and where each field came from.

This is especially important because config controls permission rules, agents, MCP, plugins, LSP, providers, tools, shell behavior, and server behavior.

### 12. Snapshots Are Helpful, But Not A Complete Undo Guarantee

The session processor records snapshots and patches around model/tool steps ([processor.ts](../opencode/packages/opencode/src/session/processor.ts#L346)). That is valuable for recovery and audit. But snapshotting can be disabled in config, and snapshot systems usually cannot provide a perfect transactional undo for all side effects: shell commands can touch files outside tracked paths, external services can be mutated, ignored or large files may be skipped, and plugin/MCP side effects may be outside the project tree.

Users should view snapshots as a recovery aid, not as a permission boundary.

### 13. The Test Suite Is Meaningful, But The Behavior Matrix Is Huge

The repository has substantial tests under `packages/opencode/test`, including tools, permissions, config, server behavior, MCP/OAuth, snapshots, and session behavior. That is a strength. The remaining risk comes from the cross-product of features: providers, models, agents, permissions, plugins, MCP servers, LSPs, Hono versus Effect HTTP API, TUI versus HTTP clients, local versus remote config, and OS-specific shell behavior.

For this kind of system, unit and parity tests are necessary but not sufficient. High-confidence releases need scenario tests for real workflows and hostile or confused configuration states.

## Overall Assessment

OpenCode has a coherent and ambitious architecture. It is not a thin wrapper around a model API. It is a local agent runtime with a real server, typed tools, extensibility, sessions, state, provider abstraction, language tooling, and multiple user interfaces. The architecture matches the product thesis: an open coding agent should be inspectable, provider-neutral, scriptable, extensible, and usable from the terminal without being trapped there.

The main weaknesses are not a lack of features. They are trust-boundary weaknesses created by features that are individually useful: permissive default permissions, optional server auth, project-local config, plugin execution, npm plugin installation, local MCP commands, broad provider compatibility, and dynamic tool mutation. These are acceptable for a trusted local developer tool if users understand them. They are more concerning for teams, untrusted repositories, remote servers, shared machines, and enterprise-managed environments.

The highest-leverage improvements would be:

1. Make unsafe server exposure harder: require auth when binding outside loopback, make the warning impossible to miss, and document the server as a privileged control plane.
2. Fix or clarify the plan-agent and `.env` permission doc/source mismatches.
3. Add tooling that explains the effective config, final agent permissions, enabled plugins, MCP tools, and provider-specific tool set for a session.
4. Strengthen editing freshness checks so approved diffs cannot be applied over externally changed files without detection.
5. Provide stricter preset profiles for untrusted repositories and enterprise use, with plugins, local MCP, auto-installs, broad bash, and remote config disabled unless explicitly enabled.

OpenCode's design is strong because it treats coding agents as programmable developer infrastructure. Its weakness is that programmable developer infrastructure needs sharper defaults and clearer trust boundaries than a normal CLI.
