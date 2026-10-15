// Prints the launch environment Highball would use for a Steam game, one KEY=VALUE per line.
// Usage: highball-env --prefix <wine prefix> --engine <engine id> [--appid <Steam app id>] [--db <highball-db.json>]

import Foundation
import HighballEnvCore

var options: [String: String] = [:]
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let name = arguments.next() {
    guard name.hasPrefix("--"), let value = arguments.next() else { break }
    options[String(name.dropFirst(2))] = value
}

guard let prefix = options["prefix"], let engine = options["engine"] else {
    print("# error: usage: highball-env --prefix <wine prefix> --engine <engine id> [--appid <id>]")
    exit(0)
}

print("# highball-env HighballKit \(HighballEnvCore.highballKitVersion)")
var gameData: GameData?
if let db = options["db"] {
    do {
        gameData = try GameData(contentsOf: URL(fileURLWithPath: db))
        print("# note: highball-db \(gameData?.commit.prefix(12) ?? "")")
    } catch {
        print("# note: highball-db unreadable, no per-game fixes")
    }
}
let request = LaunchEnvironment.Request(
    prefix: URL(fileURLWithPath: prefix), engineID: engine, appID: options["appid"].flatMap(Int.init),
    environment: ProcessInfo.processInfo.environment, gameData: gameData)
for line in LaunchEnvironment.lines(for: request) { print(line) }
