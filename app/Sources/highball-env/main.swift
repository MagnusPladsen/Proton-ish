// Prints the launch environment Highball would use for a Steam game, one KEY=VALUE per line.
// Usage: highball-env install|accept … (see below), or
//        highball-env --prefix <wine prefix> --engine <engine id> [--appid <Steam app id>] [--db <highball-db.json>] [--exe <game executable>]

import Foundation
import HighballEnvCore

var commandLine = Array(CommandLine.arguments.dropFirst())
let command = commandLine.first.flatMap { ["install", "accept", "renderers"].contains($0) ? $0 : nil }
if command != nil { commandLine.removeFirst() }
let acceptD3DMetal = commandLine.contains("--accept-d3dmetal")
commandLine.removeAll { $0 == "--accept-d3dmetal" }

var options: [String: String] = [:]
var arguments = commandLine.makeIterator()
while let name = arguments.next() {
    guard name.hasPrefix("--"), let value = arguments.next() else { break }
    options[String(name.dropFirst(2))] = value
}

// highball-env install --manifest <engine manifest> [--accept-d3dmetal]
// highball-env accept --engine <engine id>
// highball-env renderers --engine <engine id>   (available renderers, one per line)
switch command {
case "install":
    guard let manifest = options["manifest"] else {
        print("# error: usage: highball-env install --manifest <engine manifest> [--accept-d3dmetal]")
        exit(1)
    }
    do {
        let id = try await EngineInstall.install(manifest: URL(fileURLWithPath: manifest), acceptD3DMetal: acceptD3DMetal) {
            print($0)
            fflush(stdout)
        }
        print("installed \(id)")
        exit(0)
    } catch {
        print("# error: \(error)")
        exit(1)
    }
case "accept":
    guard let engine = options["engine"] else {
        print("# error: usage: highball-env accept --engine <engine id>")
        exit(1)
    }
    do {
        try EngineInstall.accept(engineID: engine)
        print("accepted \(EngineInstall.d3dmetalLicence) for \(engine)")
        exit(0)
    } catch {
        print("# error: \(error)")
        exit(1)
    }
case "renderers":
    guard let engine = options["engine"] else {
        print("# error: usage: highball-env renderers --engine <engine id>")
        exit(1)
    }
    do {
        for renderer in try EngineRenderers.available(engineID: engine) { print(renderer) }
        exit(0)
    } catch {
        print("# error: \(error)")
        exit(1)
    }
default:
    break
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
    environment: ProcessInfo.processInfo.environment, gameData: gameData,
    exe: options["exe"].map { URL(fileURLWithPath: $0) })
for line in LaunchEnvironment.lines(for: request) { print(line) }
