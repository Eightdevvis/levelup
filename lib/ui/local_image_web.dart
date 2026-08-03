import 'package:flutter/material.dart';

/// Im Browser gibt es keine lokalen Dateien.
///
/// `null` heißt: der Aufrufer zeigt seinen Platzhalter. Das ist ehrlicher als
/// ein Bild, das nie kommt.
Widget? localImage(String path, Widget Function() onError) => null;
