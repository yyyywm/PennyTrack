/// APK 构建包装脚本：自动注入真实 IP，构建完成后恢复占位符。
///
/// 用法：dart run scripts/build_apk.dart [--release|--debug|--profile]
///
/// 等价于 flutter build apk，但在构建前后自动处理 network_security_config.xml
import 'dart:io';

const _placeholder = 'YOUR_SERVER_IP';

void main(List<String> args) async {
  final projectRoot = _findProjectRoot();

  // 1. 从 api_config.dart 提取 IP
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

  // 2. 注入 IP 到 XML
  final xmlPath = '${projectRoot}android${Platform.pathSeparator}'
      'app${Platform.pathSeparator}src${Platform.pathSeparator}'
      'main${Platform.pathSeparator}res${Platform.pathSeparator}'
      'xml${Platform.pathSeparator}network_security_config.xml';
  final xmlFile = File(xmlPath);
  if (!xmlFile.existsSync()) {
    _error('network_security_config.xml 不存在：$xmlPath');
  }

  final originalXml = xmlFile.readAsStringSync();
  if (!originalXml.contains(_placeholder)) {
    _error('network_security_config.xml 中未找到 $_placeholder 占位符。'
        '请检查文件内容，或确认它未被手动修改过。');
  }

  final injectedXml = originalXml.replaceAll(_placeholder, serverIp);
  xmlFile.writeAsStringSync(injectedXml);
  print('[inject] 已将 $serverIp 注入 network_security_config.xml');

  // 3. 运行 flutter build
  final buildMode = _resolveBuildMode(args);
  final buildArgs = <String>['build', 'apk'];
  if (buildMode != null) buildArgs.add('--$buildMode');

  print('[build] 运行: flutter ${buildArgs.join(' ')} ...');
  final buildResult = await Process.start(
    'flutter',
    buildArgs,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await buildResult.exitCode;

  // 4. 无论构建成败，都恢复占位符
  xmlFile.writeAsStringSync(originalXml);
  print('[restore] network_security_config.xml 已恢复为占位符');

  if (exitCode != 0) {
    _error('flutter build apk 失败 (exit code $exitCode)');
  }

  print('[done] APK 构建完成，XML 配置已恢复安全状态');
}

String? _resolveBuildMode(List<String> args) {
  for (final arg in args) {
    if (arg == '--release') return 'release';
    if (arg == '--debug') return 'debug';
    if (arg == '--profile') return 'profile';
  }
  return null;
}

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
  final scriptDir = Platform.script.toFilePath();
  return '${File(scriptDir).parent.parent.path}${Platform.pathSeparator}';
}

Never _error(String msg) {
  stderr.writeln('[ERROR] $msg');
  exit(1);
}
