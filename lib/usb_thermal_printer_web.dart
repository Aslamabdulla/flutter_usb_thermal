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
  late int lineWidth;
  late int itemColumnWidth;
  late int qtyColumnWidth;
  late int priceColumnWidth;
  late int totalColumnWidth;
  String defaultFont = 'A';
  final int paperWidth;
  WebThermalPrinter({required this.paperWidth, required this.defaultFont}) {
    lineWidth = paperWidth == 80
        ? defaultFont == "A"
            ? 48
            : 63
        : paperWidth == 72
            ? defaultFont == "A"
                ? 42
                : 56
            : defaultFont == "A"
                ? 36
                : 50;
    itemColumnWidth =
        (lineWidth * 0.45).toInt(); // 50% of the lineWidth for item column
    qtyColumnWidth =
        (lineWidth * 0.15).toInt(); // 15% of the lineWidth for quantity column
    priceColumnWidth =
        (lineWidth * 0.20).toInt(); // 15% of the lineWidth for price column
    totalColumnWidth = (lineWidth * 0.20).toInt();
  }

  Future<dynamic> pairDevice({
    required int vendorId,
    required int productId,
    int? interfaceNo,
    int? endpointNo,
    required bool isPaired,
    dynamic device,
  }) async {
    try {
      if (kIsWeb == false) {
        return null;
      }
      interfaceNumber = interfaceNo ?? 0;
      endpointNumber = endpointNo ?? 1;
      if (!isPaired) {
        pairedDevice ??= await usbDevice.requestDevices(
            [DeviceFilter(vendorId: vendorId, productId: productId)]);
      } else {
        pairedDevice = device;
      }

      await usbDevice.open(pairedDevice);
      await usbDevice.claimInterface(pairedDevice, interfaceNumber);
      return pairedDevice;
    } catch (e) {
      return null;
    }
  }

  Future<void> printRow({
    required String item,
    required String qty,
    required String price,
    required String total,
    bool bold = false,
  }) async {
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

      await printTextAlign(row,
          alignment: TextAlign.left, bold: bold); // Left-align the whole row
    }
  }

// Function to split string into multiple lines for long items
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

  Future<void> printQrCode(String upiLink, {int qrSize = 6}) async {
    if (!kIsWeb) return; 


    qrSize = (qrSize < 1 || qrSize > 8) ? 6 : qrSize;

   
    var qrSettingsBytes = Uint8List.fromList([
      0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x43, qrSize, 
    ]);

    var qrStoreBytes = Uint8List.fromList([
      0x1d, 0x28, 0x6b, (upiLink.length + 3) & 0xFF,
      ((upiLink.length + 3) >> 8) & 0xFF, 
      0x31, 0x50, 0x30, 
      ...utf8.encode(upiLink), 
    ]);

    var qrPrintBytes = Uint8List.fromList([
      0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30, 
    ]);


    var centerAlignBytes =
        Uint8List.fromList([0x1b, 0x61, 0x01]);
    var resetAlignBytes =
        Uint8List.fromList([0x1b, 0x61, 0x00]);

    await usbDevice.transferOut(
        pairedDevice, endpointNumber, centerAlignBytes.buffer);
    await usbDevice.transferOut(
        pairedDevice, endpointNumber, qrSettingsBytes.buffer);
    await usbDevice.transferOut(
        pairedDevice, endpointNumber, qrStoreBytes.buffer);
    await usbDevice.transferOut(
        pairedDevice, endpointNumber, qrPrintBytes.buffer);
    await usbDevice.transferOut(
        pairedDevice, endpointNumber, resetAlignBytes.buffer);
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
    // Adjust this value to match your printer's character width per line
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

    // Determine the line width based on the paper size
    int lineWidth = paperWidth == 80
        ? defaultFont == "A"
            ? 48
            : 63
        : paperWidth == 72
            ? defaultFont == "A"
                ? 42
                : 56
            : defaultFont == "A"
                ? 36
                : 50; // 80mm printer gets 56 columns, 72mm gets 42

    // Create a dotted line with the appropriate number of characters
    String dottedLine = '-' * lineWidth;

    // Encode the dotted line into bytes
    var encodedText = utf8.encode("$dottedLine\n");

    // Send the bytes to the printer
    var buffer = Uint8List.fromList(encodedText).buffer;
    await usbDevice.transferOut(pairedDevice, endpointNumber, buffer);
  }

  Future<void> closePrinter() async {
    if (kIsWeb == false) {
      return;
    }
    await usbDevice.close(pairedDevice);
  }

  Future<void> cut({bool? isFull}) async {
    List<int> bytes = [];
    bytes += emptyLines(5);
    if (isFull ?? false) {
      bytes += '\x1DV0'.codeUnits;
    } else {
      bytes += '\x1DV1'.codeUnits;
    }
    final data = Uint8List.fromList(bytes);
    await usbDevice.transferOut(pairedDevice, endpointNumber, data.buffer);
  }

  List<int> emptyLines(int n) {
    List<int> bytes = [];
    if (n > 0) {
      bytes += List.filled(n, '\n').join().codeUnits;
    }
    return bytes;
  }

  void setFont(String font) {
    if (font == 'A' || font == 'B') {
      defaultFont = font;
    } else {
      defaultFont = "A";
    }
  }

  Future<void> printTextAlign(
    String text, {
    bool bold = false,
    TextAlign alignment = TextAlign.left,
    int fontSize = 1, // Font size: 1 = normal, 2 = double-size
  }) async {
    if (!kIsWeb) {
      return;
    }

    List<int> commands = [];

    if (defaultFont == 'B') {
      commands.addAll([0x1B, 0x4D, 0x01]); // Select Font B
    } else {
      commands.addAll([0x1B, 0x4D, 0x00]); // Select Font A
    }
    if (fontSize == 2) {
      commands.addAll([0x1D, 0x21, 0x11]); // Double width and height
    } else {
      commands.addAll([0x1D, 0x21, 0x00]); // Normal size
    }
    // Apply bold formatting
    if (bold) {
      commands.addAll([0x1B, 0x45, 0x01]); // Bold on
    }

    // Set font size

    // Split the text into multiple lines based on the line width
    var rows = _splitStringIntoRows(text, lineWidth ~/ fontSize);

    // Apply alignment and print each line
    for (var row in rows) {
      // Apply the desired alignment for each line
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

      // Add the row of text and apply formatting
      commands.addAll(utf8.encode(row + '\n'));
    }

    // Reset bold and font size to default
    if (bold) {
      commands.addAll([0x1B, 0x45, 0x00]); // Bold off
    }
    commands.addAll([0x1D, 0x21, 0x00]); // Reset font size

    // Reset alignment to left by default
    commands.addAll([0x1B, 0x61, 0x00]);

    // Send the commands to the printer
    var buffer = Uint8List.fromList(commands).buffer;
    await usbDevice.transferOut(pairedDevice, endpointNumber, buffer);
  }

  Future<void> printTwoColumnRow({
    required String leftLabel,
    required String rightValue,
    // Total characters per line for your printer
  }) async {
    // Calculate padding between the left label and right value
    int padding = lineWidth - leftLabel.length - rightValue.length;
    if (padding < 0) {
      padding = 1; // Prevent overlap if the label and value are too long
    }

    // Format the row with left-aligned label and right-aligned value
    String row = "${leftLabel.padRight(leftLabel.length + padding)}$rightValue";

    // Print the formatted row
    await printTextAlign(row,
        alignment: TextAlign.left); // Row is left-aligned overall
  }

  String formatRow(
    String label,
    String value,
  ) {
    // Adjust label and value column widths based on the lineWidth
    // For example, for 80mm paper (56 chars) and 72mm paper (42 chars), we define:
    int labelColumnWidth =
        (lineWidth * 0.65).toInt(); // 65% of the line width for label
    int valueColumnWidth =
        (lineWidth * 0.35).toInt(); // 35% of the line width for value

    // Truncate or pad the label to fit the label column width
    String formattedLabel =
        label.padRight(labelColumnWidth).substring(0, labelColumnWidth);

    // Truncate or pad the value to align within the value column width
    String formattedValue =
        value.padLeft(valueColumnWidth).substring(0, valueColumnWidth);

    // Combine the label and value, ensuring that both are within their respective columns
    return "$formattedLabel$formattedValue";
  }
}

enum TextAlign {
  left,
  center,
  right,
}
