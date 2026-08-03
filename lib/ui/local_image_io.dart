import 'dart:io';

import 'package:flutter/material.dart';

/// Ein Bild aus dem Dateisystem.
Widget? localImage(String path, Widget Function() onError) {
  return Image.file(
    File(path),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => onError(),
  );
}
