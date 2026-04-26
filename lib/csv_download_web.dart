import 'dart:convert';

import 'package:web/web.dart' as web;

bool downloadBytes(
  String fileName,
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) {
  final anchor = web.HTMLAnchorElement()
    ..href = Uri.dataFromBytes(
      bytes,
      mimeType: mimeType,
    ).toString()
    ..download = fileName;

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  return true;
}

bool downloadCsv(String fileName, String content) {
  return downloadBytes(
    fileName,
    utf8.encode(content),
    mimeType: 'text/csv;charset=utf-8',
  );
}
