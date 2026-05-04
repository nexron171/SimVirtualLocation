import Foundation

struct ProcessRunResult {
    let terminationStatus: Int32
    let stdout: Data
    let stderr: Data
}

/// Runs a configured `Process` to completion and collects stdout/stderr.
enum ProcessRunner {
    static func run(_ task: Process) throws -> ProcessRunResult {
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        try task.run()
        task.waitUntilExit()

        let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
        outPipe.fileHandleForReading.closeFile()
        errPipe.fileHandleForReading.closeFile()

        return ProcessRunResult(terminationStatus: task.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
