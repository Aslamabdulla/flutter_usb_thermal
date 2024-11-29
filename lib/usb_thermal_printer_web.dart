library usb_thermal_printer_web;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:usb_device/usb_device.dart'
if (dart.library.io) 'usb_device_empty.dart';

class WebThermalPrinter {
  final UsbDevice usbDevice = UsbDevice();
  var pairedDevice;

  //By Default, it is usually 0
  var interfaceNumber;

  //By Default, it is usually 1
  var endpointNumber;

  Future<void> pairDevice(
      {required int vendorId,
        required int productId,
        int? interfaceNo,
        int? endpointNo}) async {
    if (kIsWeb == false) {
      return;
    }
    interfaceNumber = interfaceNo ?? 0;
    endpointNumber = endpointNo ?? 1;
    pairedDevice ??= await usbDevice.requestDevices(
        [DeviceFilter(vendorId: vendorId, productId: productId)]);
    await usbDevice.open(pairedDevice);
    await usbDevice.claimInterface(pairedDevice, interfaceNumber);
  }
Future<void> printRow({
  required String item,
  required String qty,
  required String price,
  required String total,
  int lineWidth = 48, // Total characters per line for your printer
  bool bold =false
}) async {
  const itemColumnWidth = 24; // Max width for the Item column
  const qtyColumnWidth = 6;  // Max width for the Qty column
  const priceColumnWidth = 8; // Max width for the Price column
  const totalColumnWidth = 10; // Max width for the Total column

  // Split item into multiple lines if it's too long
  List<String> itemLines = _splitStringIntoRows(item, itemColumnWidth);

  // Ensure Qty, Price, and Total align in each row
  String formattedQty = qty.padLeft(qtyColumnWidth);
  String formattedPrice = price.padLeft(priceColumnWidth);
  String formattedTotal = total.padLeft(totalColumnWidth);

  // Print each line of the row
  for (int i = 0; i < itemLines.length; i++) {
    String itemLine = itemLines[i].padRight(itemColumnWidth);

    // Print the first row with Qty, Price, and Total; subsequent rows only include Item
    String row = (i == 0)
        ? "$itemLine$formattedQty$formattedPrice$formattedTotal"
        : itemLine;

    await printTextAlign(row, alignment: TextAlign.left,bold: bold); // Left-align the whole row
  }
}


  List<String> _splitStringIntoRows(String str, int rowWidth) {
    var rows = <String>[];
    var currentRow = '';
    for (var word in str.split(' ')) {
      if ((currentRow + word).length > rowWidth) {
        rows.add(currentRow);
        currentRow = '';
      }
      currentRow += word + ' ';
    }
    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }
    return rows;
  }

  Future<void> printBarcode(String barcodeData) async {
    if (kIsWeb == false) {
      return;
    }
    var barcodeBytes = Uint8List.fromList([
      0x1d, 0x77, 0x02, // Set barcode height to 64 dots (default is 50 dots)
      0x1d, 0x68, 0x64, // Set barcode text position to below barcode
      0x1d, 0x48, 0x02, // Set barcode text font to Font B (default is Font A)
      0x1d, 0x6b, 0x49, // Print Code 128 barcode with text
      barcodeData.length + 2, // Length of data to follow (barcodeData + {B})
      0x7b, 0x42, // Start Code B
    ]);
    var barcodeStringBytes = utf8.encode(barcodeData);
    var data = Uint8List.fromList([...barcodeBytes, ...barcodeStringBytes]);

    var centerAlignBytes = Uint8List.fromList([
      0x1b, 0x61, 0x01, // Center align
    ]);
    var centerAlignData = centerAlignBytes.buffer.asByteData();
    var resetAlignBytes = Uint8List.fromList([
      0x1b, 0x61, 0x00, // Reset align to left
    ]);
    var resetAlignData = resetAlignBytes.buffer.asByteData();

    await usbDevice.transferOut(
        pairedDevice, endpointNumber, centerAlignData.buffer);
    await usbDevice.transferOut(pairedDevice, endpointNumber, data.buffer);
    await usbDevice.transferOut(
        pairedDevice, endpointNumber, resetAlignData.buffer);
  }
Future<void> printText(
  String text, {
  bool? bold,
  bool centerAlign = false,
  int lineWidth = 48, // Adjust this value to match your printer's character width per line
}) async {
  if (kIsWeb == false) {
    return;
  }

  String formattedText = text;

  // Apply bold if needed
  if (bold ?? false) {
    formattedText = "\x1B[!0m$text\x1B[0m";
  }

  // Apply center alignment if required
  if (centerAlign) {
    var leftPadding = ((lineWidth - text.length) / 2).floor();
    formattedText = ''.padLeft(leftPadding) + text;
  }

  // Ensure the text doesn't exceed the line width
  var rows = _splitStringIntoRows(formattedText, lineWidth);

  // Print each row
  for (var row in rows) {
    var encodedText = utf8.encode(row + '\n');
    var buffer = Uint8List.fromList(encodedText).buffer;
    await usbDevice.transferOut(pairedDevice, endpointNumber, buffer);
  }
}

  Future<void> printEmptyLine() async {
    if (kIsWeb == false) {
      return;
    }
    var encodedText = utf8.encode("\n");
    var buffer = Uint8List.fromList(encodedText).buffer;
    await usbDevice.transferOut(pairedDevice, endpointNumber, buffer);
  }

  Future<void> printDottedLine() async {
    if (kIsWeb == false) {
      return;
    }
    var encodedText = utf8.encode("\n------------------------------------------------\n");
    var buffer = Uint8List.fromList(encodedText).buffer;
    await usbDevice.transferOut(pairedDevice, endpointNumber, buffer);
  }

  Future<void> closePrinter() async {
    if (kIsWeb == false) {
      return;
    }
    await usbDevice.close(pairedDevice);
  }
     Future<void> cut({bool? isFull}) async{
    List<int> bytes = [];
    bytes += emptyLines(5);
    if (isFull??false) {
      bytes += '\x1DV0'.codeUnits;
    } else {
      bytes += '\x1DV1'.codeUnits;
    }
   final data= Uint8List.fromList(bytes);
    await usbDevice.transferOut(pairedDevice, endpointNumber, data.buffer);
  }
   List<int> emptyLines(int n) {
    List<int> bytes = [];
    if (n > 0) {
      bytes += List.filled(n, '\n').join().codeUnits;
    }
    return bytes;
  }
 Future<void> printTextAlign(
  String text, {
  bool bold = false,
  TextAlign alignment = TextAlign.left,
  int fontSize = 1, // Font size: 1 = normal, 2 = double-size
  int lineWidth = 48, // Total characters per line for your printer
}) async {
  if (!kIsWeb) {
    return;
  }

  List<int> commands = [];

  // Apply alignment
  switch (alignment) {
    case TextAlign.center:
      commands.addAll([0x1B, 0x61, 0x01]); // Center align
      break;
    case TextAlign.right:
      commands.addAll([0x1B, 0x61, 0x02]); // Right align
      break;
    case TextAlign.left:
    default:
      commands.addAll([0x1B, 0x61, 0x00]); // Left align
      break;
  }

  // Apply bold
  if (bold) {
    commands.addAll([0x1B, 0x45, 0x01]); // Bold on
  }

  // Set font size
  if (fontSize == 2) {
    commands.addAll([0x1D, 0x21, 0x11]); // Double width and height
  } else {
    commands.addAll([0x1D, 0x21, 0x00]); // Normal size
  }

  // Split and add text
  var rows = _splitStringIntoRows(text, lineWidth ~/ fontSize);
  for (var row in rows) {
    commands.addAll(utf8.encode(row + '\n'));
  }

  // Reset bold and font size
  if (bold) {
    commands.addAll([0x1B, 0x45, 0x00]); // Bold off
  }
  commands.addAll([0x1D, 0x21, 0x00]); // Font size reset

  // Reset alignment
  commands.addAll([0x1B, 0x61, 0x00]);

  // Send commands to printer
  var buffer = Uint8List.fromList(commands).buffer;
  await usbDevice.transferOut(pairedDevice, endpointNumber, buffer);
}


}
String formatRow(String label, String value, int lineWidth) {
  const labelColumnWidth = 35; // Fixed width for the label column
  const valueColumnWidth = 13; // Fixed width for the value column

  // Truncate or pad the label to fit the label column width
  String formattedLabel = label.padRight(labelColumnWidth).substring(0, labelColumnWidth);

  // Truncate or pad the value to align within the value column width
  String formattedValue = value.padLeft(valueColumnWidth).substring(0, valueColumnWidth);

  // Combine the label and value
  return "$formattedLabel$formattedValue";
}



 enum TextAlign {
  left,
  center,
  right,
}
