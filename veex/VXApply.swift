import Foundation

enum VXApplyError: LocalizedError {
    case missingPackage(String)
    case blocked

    var errorDescription: String? {
        switch self {
        case .missingPackage(let n): return "falta \(n)"
        case .blocked: return "parche bloqueado"
        }
    }
}

enum VXApply {
    static let password = "Levi-externas-veex-6393*#%"

    static func url(_ file: String) -> URL? {
        let path = Bundle.main.bundlePath + "/veex/" + file
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func pidKey(_ file: String) -> String { "vx.pid." + file }

    private static func pid(_ file: String) -> UUID? {
        UserDefaults.standard.string(forKey: pidKey(file)).flatMap(UUID.init(uuidString:))
    }

    static func isOn(_ file: String) -> Bool {
        guard let id = pid(file) else { return false }
        return DevicePatchService.latestReceipt(projectID: id) != nil
    }

    static func apply(_ file: String) throws {
        let item = try install(file)
        let project: PatchProject
        if item.summary.schemaVersion >= 2, item.canInspectContents {
            project = try PatchProjectLibrary.synchronizeWorkspace(item: item)
        } else if let base = item.project {
            project = base
        } else {
            throw VXApplyError.blocked
        }
        _ = try DevicePatchService.apply(project: project)
    }

    static func restore(_ file: String) throws {
        guard let id = pid(file) else { return }
        if let receipt = DevicePatchService.latestReceipt(projectID: id) {
            _ = try DevicePatchService.inspectRestore(receipt: receipt)
            try DevicePatchService.restore(receipt: receipt, allowChangedTargets: true)
        }
        if let item = PatchProjectLibrary.load().first(where: { $0.id == id }) {
            try PatchProjectLibrary.delete(item)
        }
        UserDefaults.standard.removeObject(forKey: pidKey(file))
    }

    private static func install(_ file: String) throws -> PatchLibraryItem {
        guard let source = url(file) else { throw VXApplyError.missingPackage(file) }
        let data = try Data(contentsOf: source)
        let summary = try PatchPackageCodec.inspect(data)

        if PatchProjectLibrary.load().first(where: { $0.id == summary.packageID }) == nil {
            let decoded: DecodedPatchPackage
            if let key = try PatchKeyStore.load(for: summary) {
                decoded = try PatchPackageCodec.decode(data, contentKey: key)
            } else {
                decoded = try PatchPackageCodec.decode(data, password: password)
                try PatchKeyStore.store(decoded.contentKey, for: summary)
            }
            try PatchProjectLibrary.installImportedPackage(
                data: data,
                decoded: decoded,
                summary: summary,
                existingURL: nil
            )
        }

        guard let item = PatchProjectLibrary.load().first(where: { $0.id == summary.packageID }) else {
            throw VXApplyError.blocked
        }
        UserDefaults.standard.set(item.id.uuidString, forKey: pidKey(file))
        return item
    }
}
