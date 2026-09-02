import Darwin
import Foundation

public enum TimedProcessRunnerError: LocalizedError {
    case timedOut
    case nonzeroExit(status: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Audio conversion timed out."
        case let .nonzeroExit(status, stderr):
            return stderr.isEmpty
                ? "Audio conversion exited with status \(status)."
                : "Audio conversion exited with status \(status): \(stderr)"
        }
    }
}

public struct TimedProcessRunner {
    public let timeout: TimeInterval
    public let terminationGrace: TimeInterval

    public init(timeout: TimeInterval, terminationGrace: TimeInterval = 1) {
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    @discardableResult
    public func run(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        let stderrBox = LockedDataBox()
        let stderrFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            stderrBox.store(errorPipe.fileHandleForReading.readDataToEndOfFile())
            stderrFinished.signal()
        }

        let deadline = DispatchTime.now() + max(0, timeout)
        if exited.wait(timeout: deadline) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            if exited.wait(timeout: .now() + max(0, terminationGrace)) == .timedOut,
               process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            _ = stderrFinished.wait(timeout: .now() + 1)
            throw TimedProcessRunnerError.timedOut
        }

        _ = stderrFinished.wait(timeout: .now() + 1)
        let stderr = String(data: stderrBox.load(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw TimedProcessRunnerError.nonzeroExit(
                status: process.terminationStatus,
                stderr: stderr
            )
        }
        return stderr
    }
}

private final class LockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func load() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
