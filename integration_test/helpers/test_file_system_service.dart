import 'package:noetec/service/file_system_service.dart';

class TestFileSystemService extends FileSystemServiceImpl {
  String? nextPickPath;

  @override
  Future<String?> pickDirectory() async => nextPickPath;
}
