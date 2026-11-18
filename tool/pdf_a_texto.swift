import Foundation
import PDFKit

// Uso: pdftxt <entrada.pdf> <salida.txt>
// Escribe el texto de cada página precedido de una marca "=== PAGINA n ===".
let args = CommandLine.arguments
guard args.count == 3, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("no se pudo abrir el PDF\n".data(using: .utf8)!)
    exit(1)
}
var salida = ""
for i in 0..<doc.pageCount {
    salida += "\n=== PAGINA \(i + 1) ===\n"
    salida += doc.page(at: i)?.string ?? ""
}
try salida.write(toFile: args[2], atomically: true, encoding: .utf8)
print("paginas: \(doc.pageCount), caracteres: \(salida.count)")
