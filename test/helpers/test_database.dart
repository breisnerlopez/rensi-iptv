import 'dart:ffi';

import 'package:rensi_iptv/database/database.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';

AppDatabase createTestDatabase() {
  open.overrideFor(OperatingSystem.linux, () {
    return DynamicLibrary.open('libsqlite3.so.0');
  });
  return AppDatabase(NativeDatabase.memory());
}
