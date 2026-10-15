// Prints the launch environment Highball would use for a Steam game, one KEY=VALUE per line.
// Usage: highball-env --prefix <wine prefix> --engine <engine id> [--appid <Steam app id>]

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

let request = LaunchEnvironment.Request(
    prefix: URL(fileURLWithPath: prefix), engineID: engine, appID: options["appid"].flatMap(Int.init),
    environment: ProcessInfo.processInfo.environment)
print("# highball-env HighballKit \(HighballEnvCore.highballKitVersion)")
for line in LaunchEnvironment.lines(for: request) { print(line) }
