import Foundation

func runThroughAShell(_ command: String) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    return process
}
