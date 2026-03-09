import AppKit
import Foundation

enum ITermIntegration {

    // MARK: - Input Sanitization

    static func sanitizeTTY(_ tty: String) -> String? {
        let pattern = #"^/dev/ttys\d+$"#
        guard tty.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return tty
    }

    static func sanitizeDirectory(_ dir: String) -> String? {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "/_.-"))
            .union(.whitespaces)
        let stripped = String(dir.unicodeScalars.filter { allowed.contains($0) })
        guard !stripped.isEmpty else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: stripped, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return stripped
    }

    // MARK: - Focus Session

    static func focusSession(tty: String?, pid: Int) {
        guard isITermRunning() else {
            print("Warning: iTerm2 is not running. Cannot focus session.")
            return
        }

        let resolvedTTY: String?
        if let tty {
            resolvedTTY = sanitizeTTY(tty)
        } else {
            resolvedTTY = lookupTTY(forPID: pid)
        }

        guard let safeTTY = resolvedTTY else {
            print("Warning: Could not resolve a valid TTY for pid \(pid).")
            return
        }

        let source = """
        tell application "iTerm"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(safeTTY)" then
                  select t
                  tell w to select
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """

        executeAppleScript(source)
    }

    // MARK: - Launch New Instance

    static func launchNewInstance(in directory: String) {
        guard let safeDir = sanitizeDirectory(directory) else {
            print("Warning: Invalid directory path: \(directory)")
            return
        }

        let source = """
        tell application "iTerm"
          activate
          create window with default profile
          tell current session of current window
            write text "cd \(safeDir) && claude --dangerously-skip-permissions"
          end tell
        end tell
        """

        executeAppleScript(source)
    }

    // MARK: - Active Session TTY

    static func activeSessionTTY() -> String? {
        let source = """
        tell application "iTerm"
          if (count of windows) is 0 then return ""
          tell current session of current tab of current window
            return tty
          end tell
        end tell
        """

        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        guard let result = script?.executeAndReturnError(&error) else {
            if let error { NSLog("AppleScript error in activeSessionTTY: \(error)") }
            return nil
        }
        let tty = result.stringValue ?? ""
        guard !tty.isEmpty else { return nil }
        return sanitizeTTY(tty)
    }

    // MARK: - Helpers

    static func isITermRunning() -> Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.googlecode.iterm2"
        ).isEmpty == false
    }

    static func lookupTTY(forPID pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let ttyPath = "/dev/" + output
        return sanitizeTTY(ttyPath)
    }

    @discardableResult
    private static func executeAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let error {
            print("AppleScript error: \(error)")
            return false
        }
        return true
    }
}
