public import Foundation
import Darwin

/// Persists a capability master secret in an owner-only regular file.
///
/// This store is intended for ad-hoc development builds whose changing code
/// signature cannot reliably reopen a Data Protection Keychain item. It fails
/// closed to a process-lifetime secret when the directory or file has unsafe
/// ownership, permissions, type, or symlink identity.
public struct SocketClientCapabilityFileSecretStore: Sendable {
    private let fileURL: URL
    private let randomData: @Sendable (Int) -> Data

    /// Creates a file-backed store at an explicit app-owned location.
    public init(fileURL: URL) {
        self.init(fileURL: fileURL) { count in
            var generator = SystemRandomNumberGenerator()
            return Data((0..<count).map { _ in
                UInt8.random(in: .min ... .max, using: &generator)
            })
        }
    }

    init(
        fileURL: URL,
        randomData: @escaping @Sendable (Int) -> Data
    ) {
        self.fileURL = fileURL
        self.randomData = randomData
    }

    /// Loads the existing 32-byte secret or creates it with mode `0600`.
    ///
    /// Unsafe or unavailable storage returns a fresh process-lifetime secret;
    /// it never follows a symlink or rewrites a suspicious existing file.
    public func loadOrCreateSecret() -> Data {
        if let existing = readSecret() { return existing }
        let generated = randomData(SocketClientCapabilityAuthority.secureByteCount)
        guard generated.count == SocketClientCapabilityAuthority.secureByteCount,
              prepareDirectory(),
              publishIfAbsent(generated),
              let persisted = readSecret() else {
            return generated
        }
        return persisted
    }

    private func prepareDirectory() -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return false
        }
        var metadata = stat()
        guard directory.path.withCString({ Darwin.lstat($0, &metadata) }) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == geteuid(),
              Darwin.chmod(directory.path, S_IRUSR | S_IWUSR | S_IXUSR) == 0 else {
            return false
        }
        return true
    }

    private func readSecret() -> Data? {
        let descriptor = fileURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == geteuid(),
              metadata.st_mode & 0o777 == S_IRUSR | S_IWUSR,
              metadata.st_size == SocketClientCapabilityAuthority.secureByteCount else {
            return nil
        }

        var bytes = [UInt8](
            repeating: 0,
            count: SocketClientCapabilityAuthority.secureByteCount
        )
        var offset = 0
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(
                    descriptor,
                    buffer.baseAddress?.advanced(by: offset),
                    remaining
                )
            }
            if count > 0 {
                offset += count
            } else if count < 0, errno == EINTR {
                continue
            } else {
                return nil
            }
        }
        return Data(bytes)
    }

    private func publishIfAbsent(_ secret: Data) -> Bool {
        let descriptor = fileURL.path.withCString {
            Darwin.open(
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        if descriptor < 0 {
            // Another creator may have won the race. `readSecret()` performs
            // the complete identity and permission validation afterward.
            return errno == EEXIST
        }
        var succeeded = Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0
        if succeeded {
            succeeded = secret.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return false }
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: offset),
                        buffer.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else if count < 0, errno == EINTR {
                        continue
                    } else {
                        return false
                    }
                }
                return Darwin.fsync(descriptor) == 0
            }
        }
        Darwin.close(descriptor)
        if !succeeded {
            fileURL.path.withCString { _ = Darwin.unlink($0) }
        }
        return succeeded
    }
}
