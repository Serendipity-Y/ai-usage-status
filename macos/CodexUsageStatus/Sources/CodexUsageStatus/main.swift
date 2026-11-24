import AppKit
import Foundation

if CommandLine.arguments.contains("--capture-gemini-chat") {
    switch GeminiChatPane.read() {
    case .snapshot(let quota):
        do {
            try quota.save()
            print("Gemini 聊天额度快照已更新")
        } catch {
            fputs("无法保存 Gemini 聊天额度快照\n", stderr)
            exit(1)
        }
    case .unavailable(let reason):
        fputs("\(reason)\n", stderr)
        exit(1)
    }
    exit(0)
}

if CommandLine.arguments.contains("--once") {
    do {
        let usage = try CodexUsageFetcher.fetchSync()
        print(usage.menuTitle)
        print("Available resets: \(usage.availableResetCount.map(String.init) ?? "unknown")")
        if let gemini = try? GeminiUsageFetcher.fetchSync() {
            print("Gemini: \(gemini.cliSummary)")
        }
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
