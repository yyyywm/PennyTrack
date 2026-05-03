/// APK 构建包装脚本：自动注入真实 IP，构建完成后恢复占位符。
///
/// 用法：dart run scripts/build_apk.dart [--release|--debug|--profile] [--split] [其他 flutter build apk 参数...]
///
/// 等价于 flutter build apk，但在构建前后自动处理 network_security_config.xml。
/// 已知 build mode 标志和 --split 会被识别，其余参数原样转发给 flutter。
/// 分架构打包示例：dart run scripts/build_apk.dart --release --split
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
  final parsed = _parseArgs(args);
  final buildArgs = <String>['build', 'apk'];
  if (parsed.buildMode != null) buildArgs.add('--${parsed.buildMode}');
  if (parsed.splitPerAbi) buildArgs.add('--split-per-abi');
  buildArgs.addAll(parsed.passthrough);

  print('[build] 运行: flutter ${buildArgs.join(' ')} ...');
  final buildResult = await Process.start(
    'flutter',
    buildArgs,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  final exitCode = await buildResult.exitCode;

  // 4. 无论构建成败，都恢复占位符
  xmlFile.writeAsStringSync(originalXml);
  print('[restore] network_security_config.xml 已恢复为占位符');

  if (exitCode != 0) {
    _error('flutter build apk 失败 (exit code $exitCode)');
  }

  print('[done] APK 构建完成，XML 配置已恢复安全状态');

  // 5. 输出 APK 路径信息
  _printApkInfo(projectRoot, parsed.splitPerAbi);
}

class _ParsedArgs {
  final String? buildMode;
  final bool splitPerAbi;
  final List<String> passthrough;
  _ParsedArgs(this.buildMode, this.splitPerAbi, this.passthrough);
}

_ParsedArgs _parseArgs(List<String> args) {
  String? mode;
  var splitPerAbi = false;
  final rest = <String>[];
  for (final arg in args) {
    if (arg == '--release') {
      mode = 'release';
    } else if (arg == '--debug') {
      mode = 'debug';
    } else if (arg == '--profile') {
      mode = 'profile';
    } else if (arg == '--split' || arg == '--split-per-abi') {
      splitPerAbi = true;
    } else {
      rest.add(arg);
    }
  }
  return _ParsedArgs(mode, splitPerAbi, rest);
}

void _printApkInfo(String projectRoot, bool splitPerAbi) {
  final buildDir = Directory(
    '${projectRoot}build${Platform.pathSeparator}'
    'app${Platform.pathSeparator}outputs${Platform.pathSeparator}flutter-apk',
  );
  if (!buildDir.existsSync()) return;

  final apkPattern = splitPerAbi ? RegExp(r'app-.*\.apk$') : RegExp(r'app\.apk$');
  final files = buildDir
      .listSync()
      .whereType<File>()
      .where((f) => apkPattern.hasMatch(f.path.split(Platform.pathSeparator).last))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) return;

  print('\n[output] 生成的 APK：');
  for (final file in files) {
    final name = file.path.split(Platform.pathSeparator).last;
    final sizeBytes = file.lengthSync();
    final sizeMb = sizeBytes / (1024 * 1024);
    print('  ${sizeMb.toStringAsFixed(2)} MB  ->  ${file.path}');
  }
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
