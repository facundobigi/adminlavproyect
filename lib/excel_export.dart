import 'package:excel/excel.dart';

import 'csv_download.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const _pesoFormatCode = r'"$" #,##0.00;-"$" #,##0.00';

CellStyle pesoCellStyle() => CellStyle(
      numberFormat: const CustomNumericNumFormat(formatCode: _pesoFormatCode),
    );

CellValue? excelCell(Object? value) {
  if (value == null) return null;
  if (value is int) return IntCellValue(value);
  if (value is num) return DoubleCellValue(value.toDouble());
  if (value is bool) return BoolCellValue(value);
  if (value is DateTime) return DateTimeCellValue.fromDateTime(value);
  return TextCellValue(value.toString());
}

void appendExcelRow(Sheet sheet, Iterable<Object?> values) {
  sheet.appendRow(values.map(excelCell).toList());
}

void setColumnWidths(Sheet sheet, List<double> widths) {
  for (var i = 0; i < widths.length; i++) {
    sheet.setColumnWidth(i, widths[i]);
  }
}

void applyStyleToColumn(
  Sheet sheet,
  int columnIndex,
  CellStyle style, {
  int startRow = 0,
  int? endRow,
}) {
  final lastRow = endRow ?? sheet.maxRows - 1;
  for (var row = startRow; row <= lastRow; row++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(
      columnIndex: columnIndex,
      rowIndex: row,
    ));
    cell.cellStyle = style;
  }
}

bool downloadExcel(String fileName, Excel workbook) {
  final bytes = workbook.encode();
  if (bytes == null) return false;
  return downloadBytes(fileName, bytes, mimeType: _xlsxMime);
}
