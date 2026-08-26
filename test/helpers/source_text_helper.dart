import 'dart:io';

String readSourceText(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
