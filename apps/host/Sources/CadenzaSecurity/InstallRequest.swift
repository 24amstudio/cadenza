import Foundation

public struct InstallRequest: Codable, Sendable {
    public var applicationPath: String
    public var archivePath: String
    public var manifestPath: String
    public var signaturePath: String
    public var publicKeySpkiBase64: String
    public var repository: String
    public var parentPid: Int32
    public var currentBuild: Int64
    public var resultPath: String

    public init(
        applicationPath: String, archivePath: String, manifestPath: String, signaturePath: String,
        publicKeySpkiBase64: String, repository: String, parentPid: Int32,
        currentBuild: Int64, resultPath: String
    ) {
        self.applicationPath = applicationPath
        self.archivePath = archivePath
        self.manifestPath = manifestPath
        self.signaturePath = signaturePath
        self.publicKeySpkiBase64 = publicKeySpkiBase64
        self.repository = repository
        self.parentPid = parentPid
        self.currentBuild = currentBuild
        self.resultPath = resultPath
    }
}
