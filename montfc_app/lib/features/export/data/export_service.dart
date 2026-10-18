import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/export_document.dart';
import 'docx_writer.dart';
import 'pdf_writer.dart';

enum ExportFormat {
  docx('Word', 'docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  pdf('PDF', 'pdf', 'application/pdf');

  const ExportFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

/// Génère le fichier puis ouvre le partage Android (WhatsApp, e-mail,
/// Drive, Fichiers…). Les fichiers exportés sont libres : aucune protection.
class ExportService {
  ExportService({Future<Directory> Function()? directory, Future<ByteData> Function(String)? loadAsset})
      : _directory = directory ?? getTemporaryDirectory,
        _loadAsset = loadAsset ?? rootBundle.load;

  final Future<Directory> Function() _directory;
  final Future<ByteData> Function(String) _loadAsset;
  PdfFonts? _fonts;

  Future<PdfFonts> _pdfFonts() async {
    final a = PdfFonts.assetPaths;
    return _fonts ??= PdfFonts.fromBytes(
      regular: await _loadAsset(a.regular),
      bold: await _loadAsset(a.bold),
      italic: await _loadAsset(a.italic),
      boldItalic: await _loadAsset(a.boldItalic),
    );
  }

  Future<Uint8List> bytes(ExportDocument doc, ExportFormat format) async => switch (format) {
        ExportFormat.docx => DocxWriter().write(doc),
        ExportFormat.pdf => PdfWriter(await _pdfFonts()).write(doc),
      };

  /// Écrit le fichier dans le dossier temporaire de l'application.
  Future<File> save(ExportDocument doc, ExportFormat format) async {
    final dir = Directory(p.join((await _directory()).path, 'exports'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, doc.fileName(format.extension)));
    return file.writeAsBytes(await bytes(doc, format), flush: true);
  }

  Future<void> share(ExportDocument doc, ExportFormat format) async {
    final file = await save(doc, format);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: format.mimeType)],
      subject: doc.title,
      text: '${doc.title} (préparé avec MonTFC)',
    ));
  }
}
