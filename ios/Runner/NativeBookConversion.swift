import Foundation
import PDFKit

/// 原生 PDF 文本提取；其余格式由纯 Dart 转换器处理。
final class NativeBookConversion {
  private let documents: ManagedBookDocuments
  private let portableRoot: URL

  init(documents: ManagedBookDocuments, portableRoot: URL) throws {
    self.documents = documents
    self.portableRoot = portableRoot
  }

  func extractPdf(_ path: String, output: String, name: String) throws {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
      throw BookDocumentFailure(code: "pdf_unavailable", message: "无法打开这个 PDF：\(name)")
    }
    let text = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw BookDocumentFailure(code: "pdf_empty", message: "PDF 没有可提取的文字：\(name)")
    }
    do {
      try text.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
    } catch {
      throw BookDocumentFailure(code: "pdf_write", message: "PDF 文本写入失败：\(name)")
    }
  }

  func extractKindle(_ path: String, output: String) throws -> [String: Any] {
    throw BookDocumentFailure(code: "kindle_unavailable", message: "Kindle 转换在当前构建中未启用")
  }
}
