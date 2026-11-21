import Foundation

/// 电子书转换占位：只做最小实现，避免工程因缺文件而无法编译。
final class NativeBookConversion {
  private let documents: ManagedBookDocuments
  private let portableRoot: URL

  init(documents: ManagedBookDocuments, portableRoot: URL) throws {
    self.documents = documents
    self.portableRoot = portableRoot
  }

  func extractPdf(_ path: String, output: URL, name: String) throws {
    throw BookDocumentFailure(code: "pdf_unavailable", message: "PDF 转换在当前构建中未启用")
  }

  func extractKindle(_ path: String, output: URL) throws -> [String: Any] {
    throw BookDocumentFailure(code: "kindle_unavailable", message: "Kindle 转换在当前构建中未启用")
  }
}
