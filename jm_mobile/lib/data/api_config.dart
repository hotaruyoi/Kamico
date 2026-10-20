import '../domain/models.dart';

class ApiConfig {
  const ApiConfig({
    this.apiHosts = const [
      'https://www.cdnhjk.net',
      'https://www.cdngwc.cc',
      'https://www.cdngwc.net',
      'https://www.cdngwc.club',
    ],
    this.imageHost = 'https://cdn-msp.jmapiproxy1.cc',
    this.version = '2.1.11',
    this.tokenSecret = '18comicAPP',
    this.dataSecret = '185Hcomic3PAPP7R',
  });
  final List<String> apiHosts;
  final String imageHost;
  final String version;
  final String tokenSecret;
  final String dataSecret;
  factory ApiConfig.fromJson(Json json) => ApiConfig(
    apiHosts: strings(json['apiHosts']),
    imageHost: '${json['imageHost']}',
    version: '${json['version']}',
    tokenSecret: '${json['tokenSecret']}',
    dataSecret: '${json['dataSecret']}',
  );
  Json toJson() => {
    'apiHosts': apiHosts,
    'imageHost': imageHost,
    'version': version,
    'tokenSecret': tokenSecret,
    'dataSecret': dataSecret,
  };

  void validate() {
    if (apiHosts.isEmpty ||
        version.trim().isEmpty ||
        tokenSecret.isEmpty ||
        dataSecret.isEmpty) {
      throw const FormatException('线路、版本和协议参数不能为空');
    }
    for (final host in [...apiHosts, imageHost]) {
      final uri = Uri.tryParse(host);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          (uri.path != '' && uri.path != '/') ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException('线路必须为 HTTPS 域名，例如 https://example.com');
      }
    }
  }
}
