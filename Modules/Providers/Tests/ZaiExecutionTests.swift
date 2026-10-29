import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Z.ai on stubbed connections: the key comes from Settings, Claude Code's own
/// settings file (only when it points at a Z.ai host), or an environment
/// variable, and the host comes with it.
@MainActor @Suite
struct ZaiExecutionTests {
    nonisolated static let body = #"{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"percentage":13},{"type":"TOKENS_LIMIT","unit":6,"percentage":46},{"type":"TIME_LIMIT","unit":5,"percentage":1}]}}"#

    /// One `billing/balance` line as ZCode's host writes it, trimmed to the
    /// fields the mapping reads: balances with no window at the top level,
    /// and `payload.data` with the plan and the balance that carries one.
    nonisolated static let zcodeLog = "[2026-10-29 23:15:07.804] [info] [pid:52854] [main] [host-log] (local-1) [host] [2026-10-29 23:15:07.804] [pid:52883] [usage-stats] billing/balance 请求完成 {\"balanceCount\":1,\"balances\":[{\"entitlement_id\":\"ent-zcode-v3-start-plan-1029-1\",\"show_name\":\"GLM-5.3-Flash\",\"total_units\":300000000,\"used_units\":34363915,\"remaining_units\":265636085,\"available_units\":265636085,\"reserved_units\":null}],\"code\":0,\"durationMs\":660,\"msg\":\"\",\"payload\":{\"code\":0,\"msg\":\"\",\"data\":{\"server_time\":1793312107,\"plans\":[{\"user_plan_id\":\"upl_1\",\"plan_id\":\"zcode-v3-start-plan-1029\",\"name\":\"ZCODE GLOBAL BUILD\"}],\"balances\":[{\"bucket_id\":\"bucket_1\",\"user_plan_id\":\"upl_1\",\"plan_id\":\"zcode-v3-start-plan-1029\",\"entitlement_id\":\"ent-zcode-v3-start-plan-1029-1\",\"show_name\":\"GLM-5.3-Flash\",\"total_units\":300000000,\"used_units\":34363915,\"remaining_units\":265636085,\"period_start\":1793277585,\"period_end\":1793322000,\"expires_at\":1793322000}]}},\"planCount\":1,\"plans\":[{\"name\":\"ZCODE GLOBAL BUILD\",\"plan_id\":\"zcode-v3-start-plan-1029\"}]}"

    /// Answers on `host` for the key `key` only; anything else is a 400.
    /// `log` seeds the ZCode host log the api source hands off to when it
    /// finds no key (or its key is refused) on this Mac.
    private func make(config: [String: Any]? = nil, platform: String? = nil, envVar: String? = nil,
                      vault: MemoryVault = MemoryVault(), environment: [String: String] = [:],
                      loginShell: [String: String] = [:], status: Int = 200, seen: Seen = Seen(),
                      log: String? = nil) throws -> Provider {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if let config {
            let folder = home.appendingPathComponent(".claude")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent("settings.json"))
        }
        if let log {
            let logs = home.appendingPathComponent(".zcode/v2/logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            try log.write(to: logs.appendingPathComponent("2026-10-29.log"), atomically: true, encoding: .utf8)
        }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            guard request.url?.path == "/api/monitor/usage/quota/limit", request.timeoutInterval == 10,
                  request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en" else {
                return (Data(), StubbedProvider.response(400))
            }
            seen.record(host: request.url?.host, key: request.value(forHTTPHeaderField: "Authorization"))
            return (Data(Self.body.utf8), StubbedProvider.response(status))
        }
        let settings = InMemoryProviderSettings()
        settings.setValue(platform, "platform", forProvider: "zai")
        settings.setValue(envVar, "glmAuthEnvVar", forProvider: "zai")
        let definition = try ProviderFactory.builtIn("zai")
        return Provider(definition: definition, settings: settings, makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), loginShell: { loginShell[$0] },
                             environment: { environment[$0] }, homeDirectory: home, now: { Date() })
        }, vault: vault)
    }

    final class Seen: @unchecked Sendable {
        private(set) var host: String?
        private(set) var key: String?
        func record(host: String?, key: String?) { self.host = host; self.key = key }
    }

    /// ZCode's `message` table, as ~/.zcode/cli/db/db.sqlite keeps it.
    private static func messageTable(rows: [String]) -> String {
        """
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            data TEXT NOT NULL,
            sequence INTEGER
        );
        """ + rows.joined(separator: " ")
    }

    private static func messageRow(id: String, at: Int64, role: String, tokens: String) -> String {
        let data = #"{"role": "\#(role)", "modelId": "GLM-5.3-Flash", "path": {"cwd": "/Users/joakimthomter/Desktop/10_SYSTEMS/16_AI_QUOTA_TRACKER"}, "time": {"created": \#(at)}, "tokens": \#(tokens), "cost": 0}"#
        return "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES ('\(id)', 'session_1', \(at), \(at), '\(data)');"
    }

    @Test func `should show Z.ai, on, with its subscription page as the dashboard`() throws {
        let provider = try make()
        #expect(provider.name == "Z.ai")
        #expect(!provider.defaultAccount.isPaused)
        #expect(provider.plainDashboardURL?.absoluteString == "https://z.ai/subscribe")
    }

    @Test func `should show the session, weekly and MCP quotas from api.z.ai when the key is saved in Settings`() async throws {
        let seen = Seen()
        let quotas = try await make(vault: MemoryVault(["zai.apiKey": "saved"]), seen: seen).refreshPlain().quotas
        #expect(quotas.map(\.quotaType) == [.session, .weekly, .timeLimit("MCP")])
        #expect(quotas[0].window?.length == 18000)
        #expect(quotas[1].window?.length == 604800)
        #expect(quotas[2].window?.length == nil)
        #expect(seen.host == "api.z.ai")
        #expect(seen.key == "Bearer saved")
    }

    @Test(arguments: [("zhipu", "open.bigmodel.cn"), ("dev", "dev.bigmodel.cn")])
    func `should ask the chosen platform's host with the saved key`(_ platform: String, _ host: String) async throws {
        let seen = Seen()
        _ = try await make(platform: platform, vault: MemoryVault(["zai.apiKey": "saved"]), seen: seen).refreshPlain()
        #expect(seen.host == host)
    }

    @Test func `should use Claude Code's key and host when Claude Code's settings point at Z.ai`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "from-config", "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic"]]
        _ = try await make(config: config, seen: seen).refreshPlain()
        #expect(seen.host == "open.bigmodel.cn")
        #expect(seen.key == "Bearer from-config")
    }

    @Test func `should use a Z.ai provider entry from Claude Code's settings`() async throws {
        let seen = Seen()
        let config = ["providers": [["api_key": "from-provider", "base_url": "https://api.z.ai/api/anthropic"]]]
        _ = try await make(config: config, seen: seen).refreshPlain()
        #expect(seen.host == "api.z.ai")
        #expect(seen.key == "Bearer from-provider")
    }

    @Test func `should never send Claude Code's key to Z.ai when Claude Code's settings point elsewhere`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "anthropic-key", "ANTHROPIC_BASE_URL": "https://api.anthropic.com"]]
        await #expect(throws: UsageError.self) { try await make(config: config, seen: seen).refreshPlain() }
        #expect(seen.key == nil)
    }

    @Test func `should never send the key when Claude Code points at a look-alike of Z.ai's host`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "key", "ANTHROPIC_BASE_URL": "https://api.z.ai.example.com"]]
        await #expect(throws: UsageError.self) { try await make(config: config, seen: seen).refreshPlain() }
        #expect(seen.key == nil)
    }

    @Test func `should use the key from the environment variable the person named`() async throws {
        let seen = Seen()
        _ = try await make(envVar: "MY_GLM_KEY", environment: ["MY_GLM_KEY": "from-env"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-env")
        #expect(seen.host == "api.z.ai")
    }

    @Test func `should find the key the person exported only in their login shell (#170)`() async throws {
        let seen = Seen()
        _ = try await make(envVar: "MY_GLM_KEY", loginShell: ["MY_GLM_KEY": "from-shell"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-shell")
    }

    @Test func `should prefer the app's own environment to the login shell`() async throws {
        let seen = Seen()
        _ = try await make(environment: ["ZAI_API_KEY": "from-env"], loginShell: ["ZAI_API_KEY": "from-shell"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-env")
    }

    @Test func `should use ZAI_API_KEY when the person named no variable`() async throws {
        let seen = Seen()
        _ = try await make(environment: ["ZAI_API_KEY": "from-env"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-env")
    }

    @Test func `should fail to read usage when there is no key anywhere`() async throws {
        await #expect(throws: UsageError.self) { try await make().refreshPlain() }
    }

    @Test func `should use an added login's own key and platform, never the environment`() async throws {
        let seen = Seen()
        let vault = MemoryVault()
        let provider = try make(vault: vault, environment: ["ZAI_API_KEY": "from-env"], seen: seen)
        let work = try provider.accounts.add(filling: ["apiKey": "work", "platform": "zhipu"])
        _ = try await provider.refresh(work)
        #expect(seen.key == "Bearer work")
        #expect(seen.host == "open.bigmodel.cn")
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.self) { try await provider.refresh(work) }
    }

    @Test(arguments: [401, 403]) func `should fall back to ZCode's log when Z.ai refuses the saved key`(_ code: Int) async throws {
        // A refused key hands off to ZCode's own data source before any
        // failure surfaces; with the log present, the login answers from it.
        let provider = try make(vault: MemoryVault(["zai.apiKey": "saved"]), status: code, log: Self.zcodeLog)
        let snapshot = try await provider.refreshPlain()
        #expect(provider.defaultAccount.answeredBy == "zcode")
        #expect(snapshot.quotas.first?.quotaType == .session)
    }

    @Test func `should hand off to ZCode's local log when no Z.ai API key is set`() async throws {
        let provider = try make(log: Self.zcodeLog)
        #expect(await provider.isPlainAvailable())
        let snapshot = try await provider.refreshPlain()
        #expect(snapshot.quotas.first?.quotaType == .session)
        #expect(abs((snapshot.quotas.first?.percentRemaining ?? 0) - 88.54536166666667) < 0.001)
        #expect(snapshot.quotas.contains { $0.quotaType == .modelSpecific("GLM-5.3-Flash (265.6M/300M)") })
        #expect(snapshot.accountTier == .custom("ZCODE GLOBAL BUILD"))
        #expect(provider.defaultAccount.answeredBy == "zcode")
    }

    @Test func `should read ZCode's database as usage history with cache reads inside input`() async throws {
        let definition = try #require(try ProviderFactory.builtIn("zai").usageHistory)
        guard case .sqlite(let call) = definition.records.source else {
            Issue.record("Z.ai's usage history is not read from ZCode's database")
            return
        }
        #expect(definition.records.shapes.first?.tokens.inputIncludesCacheRead == true)

        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let database = home.appendingPathComponent(".zcode/cli/db/db.sqlite")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try SQLiteFiles.make(at: database, Self.messageTable(rows: [
            Self.messageRow(id: "user_1", at: now - 120_000, role: "user",
                            tokens: #"{"input": 10, "output": 0, "reasoning": 0, "cache": {"write": 0, "read": 0}}"#),
            Self.messageRow(id: "assistant_1", at: now - 60_000, role: "assistant",
                            tokens: #"{"input": 300475, "output": 1005, "reasoning": 0, "cache": {"write": 0, "read": 300160}}"#),
        ]))

        let rows = try SQLiteFiles.rows(at: database, call.queries[0].query)
        #expect(rows.map { $0["id"] as? String } == ["assistant_1"])
        #expect(rows[0]["model"] as? String == "GLM-5.3-Flash")
        #expect((rows[0]["at"] as? NSNumber)?.intValue == Int((now - 60_000) / 1000))

        let log = DataSources.makeUsageLog(definition, scripts: { _ in nil }, environment: { _ in nil }, homeDirectory: home)
        let days = await log.days(last: 1)
        #expect(days[0].totalTokens == 1_320) // (300475 − 300160 cached rereads) + 1005 written; 301480 without the flag
    }
}
