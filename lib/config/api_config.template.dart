/// 后端 API 地址配置模板
///
/// 使用说明：
/// 1. 复制本文件为同目录下的 api_config.dart
/// 2. 在 api_config.dart 中填入你自己的后端地址
/// 3. api_config.dart 已被 .gitignore 忽略，不会提交到版本控制
///
/// 注意：请勿直接修改本模板文件，也不要把真实地址写在这里。
class ApiConfig {
  /// 生产环境后端地址（请替换为你自己搭建的服务器）
  static const String productionUrl = 'http://YOUR_SERVER_IP:5300';

  /// Android 模拟器访问宿主机的地址（本地开发时通常无需修改）
  static const String emulatorUrl = 'http://10.0.2.2:5300';
}
