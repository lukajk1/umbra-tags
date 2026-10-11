import 'dart:io';

/// Deletes a test's temporary library folder. On Windows the library worker,
/// SQLite or an image codec can hold a file for a moment after the app is
/// torn down (errno 32), so retry briefly; if it is still locked, leave it in
/// the system temp folder rather than failing a test whose checks passed.
void deleteTempDir(Directory directory) {
  for (var attempt = 0; attempt < 30; attempt++) {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      sleep(const Duration(milliseconds: 100));
    }
  }
  stderr.writeln('Left locked temp folder behind: ${directory.path}');
}
