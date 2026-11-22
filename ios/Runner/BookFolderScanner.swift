import Foundation

/// 公开源码构建可用的导入格式策略。与 Dart 的 book_import_limits.dart 对齐。
enum BookImportFormatPolicy {
  static let extensions: Set<String> = [
    "txt", "epub", "mobi", "azw", "azw3", "prc", "fb2", "pdf",
    "docx", "odt", "rtf", "html", "htm", "xhtml", "md", "markdown", "zip",
  ]
  static func byteLimit(_ ext: String) -> Int {
    switch ext.lowercased() {
    case "zip": return 512 * 1024 * 1024
    case "epub", "pdf", "docx", "odt": return 512 * 1024 * 1024
    case "mobi", "azw", "azw3", "prc": return 256 * 1024 * 1024
    case "html", "htm", "xhtml", "md", "markdown": return 32 * 1024 * 1024
    default: return 128 * 1024 * 1024
    }
  }
}

/// 本地文件夹扫描占位：状态可保存，扫描返回空列表。
final class BookFolderScanner {
  private let stateFile: URL
  private let documentsDirectory: URL
  private var formatList: [String] = ["txt", "epub"]
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
      "formats": formatList,
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

  func formats() throws -> [String] { formatList }

  func setFormats(_ extensions: [String]) throws {
    formatList = extensions.map { $0.lowercased() }
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
      "formats": formatList,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    try data.write(to: stateFile, options: .atomic)
  }
}
