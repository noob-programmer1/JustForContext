import Foundation

/// Detects and manages git branch state for workspaces.
enum GitService {
    /// Read the current branch name from a git repository.
    /// Walks up the directory tree to find the nearest `.git` directory.
    static func currentBranch(at projectPath: String) -> String? {
        guard let gitDir = findGitDir(from: projectPath) else { return nil }
        let gitHead = gitDir.appendingPathComponent("HEAD")

        guard let content = try? String(contentsOf: gitHead, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        // HEAD file contains "ref: refs/heads/<branch-name>" or a commit hash
        if content.hasPrefix("ref: refs/heads/") {
            return String(content.dropFirst("ref: refs/heads/".count))
        }

        // Detached HEAD — return short hash
        return String(content.prefix(7))
    }

    /// Walk up from `startPath` to find the nearest `.git` directory.
    private static func findGitDir(from startPath: String) -> URL? {
        var current = URL(fileURLWithPath: startPath)
        let fm = FileManager.default

        // Walk up at most 10 levels
        for _ in 0..<10 {
            let gitDir = current.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitDir.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return gitDir
                }
                // .git can also be a file (worktrees): "gitdir: /path/to/actual/.git/worktrees/..."
                if let content = try? String(contentsOf: gitDir, encoding: .utf8),
                   content.hasPrefix("gitdir: ") {
                    let refPath = content.dropFirst("gitdir: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                    return URL(fileURLWithPath: refPath)
                }
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break } // reached root
            current = parent
        }
        return nil
    }

    /// Check if the repository has uncommitted changes.
    static func isDirty(at projectPath: String) -> Bool {
        let gitRoot = findGitRoot(from: projectPath) ?? projectPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", gitRoot, "status", "--porcelain"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    /// Switch to a branch, stashing changes if needed.
    static func checkout(branch: String, at projectPath: String) async throws {
        let gitRoot = findGitRoot(from: projectPath) ?? projectPath
        let dirty = isDirty(at: gitRoot)

        if dirty {
            try await runGit(["stash", "push", "-m", "DevSwitch auto-stash"], at: gitRoot)
        }

        try await runGit(["checkout", branch], at: gitRoot)

        if dirty {
            // Try to pop stash, ignore if it fails (e.g. conflicts)
            try? await runGit(["stash", "pop"], at: gitRoot)
        }
    }

    /// List local branches for a repository.
    static func branches(at projectPath: String) -> [String] {
        let gitRoot = findGitRoot(from: projectPath) ?? projectPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", gitRoot, "branch", "--format=%(refname:short)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    /// Find the git repository root directory from a starting path.
    private static func findGitRoot(from startPath: String) -> String? {
        guard let gitDir = findGitDir(from: startPath) else { return nil }
        // .git dir is at <root>/.git, so parent is the root
        return gitDir.deletingLastPathComponent().path
    }

    private static func runGit(_ args: [String], at projectPath: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", projectPath] + args
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: GitError.commandFailed(args.joined(separator: " ")))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum GitError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd):
            return "Git command failed: \(cmd)"
        }
    }
}
