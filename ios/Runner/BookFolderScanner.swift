import Foundation

/// 本地文件夹扫描占位：状态可保存，扫描返回空列表。
final class BookFolderScanner {
  private let stateFile: URL
  private let documentsDirectory: URL
  private var formats: [String] = ["txt", "epub"]
  private var automatic = false
  private var selected: URL?

  init(stateFile: URL, documentsDirectory: URL) throws {
    self.stateFile = stateFile
    self.documentsDirectory = documentsDirectory
    try? FileManager.default.createDirectory(
      at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
  }

  func info() throws -> [String: Any] {
    [
      "folder": selected?.path ?? documentsDirectory.path,
      "automatic": automatic,
      "formats": formats,
      "count": 0,
    ]
  }

  func selectApplicationDocuments() throws -> [String: Any] {
    selected = documentsDirectory
    try save()
    return try info()
  }

  func select(_ url: URL) throws -> [String: Any] {
    selected = url
    try save()
    return try info()
  }

  func formats() throws -> [String] { formats }

  func setFormats(_ extensions: [String]) throws {
    formats = extensions.map { $0.lowercased() }
    try save()
  }

  func setAutomatic(_ value: Bool) throws {
    automatic = value
    try save()
  }

  func disconnect() throws {
    selected = nil
    try save()
  }

  func scan() throws -> [[String: Any]] { [] }

  func stage(_ token: String, documents: ManagedBookDocuments) throws -> [String: Any] {
    throw BookDocumentFailure(code: "scan_unavailable", message: "文件夹扫描在当前构建中未启用")
  }

  func link(_ token: String, documents: LinkedBookDocuments) throws -> [String: Any] {
    throw BookDocumentFailure(code: "scan_unavailable", message: "文件夹扫描在当前构建中未启用")
  }

  func markImported(_ token: String) throws {}

  func finish() throws {}

  private func save() throws {
    let payload: [String: Any] = [
      "folder": selected?.path as Any,
      "automatic": automatic,
      "formats": formats,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    try data.write(to: stateFile, options: .atomic)
  }
}
