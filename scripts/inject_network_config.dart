/// 构建前注入脚本：将 network_security_config.xml 中的 YOUR_SERVER_IP
/// 替换为 api_config.dart 中 productionUrl 的真实 IP。
///
/// 用法：dart run scripts/inject_network_config.dart
/// 通常在 flutter build apk 之前手动运行，或集成到 CI/构建流程中。
import 'dart:io';

void main() {
  final projectRoot = _findProjectRoot();

  // 1. 读取 api_config.dart 提取 IP
  final apiConfigPath =
      '${projectRoot}lib${Platform.pathSeparator}config${Platform.pathSeparator}api_config.dart';
  final apiConfigFile = File(apiConfigPath);
  if (!apiConfigFile.existsSync()) {
    _error('api_config.dart 不存在。请先复制 api_config.template.dart 为 '
        'api_config.dart 并填入你的后端地址。');
  }

  final apiConfigContent = apiConfigFile.readAsStringSync();
  final ipMatch = RegExp(
    'productionUrl\\s*=\\s*["\']http://([^"\']+):\\d+["\']',
  ).firstMatch(apiConfigContent);

  if (ipMatch == null) {
    _error('无法从 api_config.dart 解析 productionUrl 的 IP 地址，'
        '请检查格式是否为 http://IP:PORT');
  }
  final serverIp = ipMatch.group(1)!;

  // 2. 替换 network_security_config.xml
  final xmlPath = '${projectRoot}android${Platform.pathSeparator}'
      'app${Platform.pathSeparator}src${Platform.pathSeparator}'
      'main${Platform.pathSeparator}res${Platform.pathSeparator}'
      'xml${Platform.pathSeparator}network_security_config.xml';
  final xmlFile = File(xmlPath);
  if (!xmlFile.existsSync()) {
    _error('network_security_config.xml 不存在：$xmlPath');
  }

  var xmlContent = xmlFile.readAsStringSync();

  if (!xmlContent.contains('YOUR_SERVER_IP')) {
    if (xmlContent.contains(serverIp)) {
      print('network_security_config.xml 已包含正确 IP ($serverIp)，无需替换。');
      return;
    }
    _error('network_security_config.xml 中未找到 YOUR_SERVER_IP 占位符，'
        '请检查文件内容。');
  }

  xmlContent = xmlContent.replaceAll('YOUR_SERVER_IP', serverIp);
  xmlFile.writeAsStringSync(xmlContent);

  print('成功注入 IP：$serverIp -> network_security_config.xml');
}

/// 从脚本所在位置向上查找项目根目录（含 pubspec.yaml）
String _findProjectRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      return '${dir.path}${Platform.pathSeparator}';
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // 回退到脚本所在目录的上两级（scripts/ -> 项目根）
  final scriptDir = Platform.script.toFilePath();
  return '${File(scriptDir).parent.parent.path}${Platform.pathSeparator}';
}

Never _error(String msg) {
  stderr.writeln('[ERROR] $msg');
  exit(1);
}
