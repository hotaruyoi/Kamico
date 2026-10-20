import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/jm_client.dart';
import 'app.dart';
import 'settings.dart';
import 'design_system.dart';
import 'translations.dart';

String failureMessage(Object error) => switch (error) {
  ApiException e when e.unauthorized => '登录已失效，请重新登录后重试',
  ApiException e => e.message,
  FileSystemException() => '文件操作未完成，请检查文件、存储空间和目录授权',
  PlatformException() => '系统未完成此操作，请检查目录授权或可用应用后重试',
  FormatException e => e.message,
  _ => '操作未完成，请稍后重试',
};

class AppFailure extends StatelessWidget {
  const AppFailure({
    super.key,
    required this.error,
    required this.retry,
    this.session,
  });
  final Object error;
  final VoidCallback retry;
  final AppSession? session;
  @override
  Widget build(BuildContext context) {
    final auth =
        session?.authExpired == true ||
        error is ApiException && (error as ApiException).unauthorized;
    final storage = error is FileSystemException || error is PlatformException;
    final firstPicLogin =
        auth && session?.isPic == true && session?.authExpired != true;
    return AppStatus(
      icon: auth
          ? Icons.lock_outline
          : storage
          ? Icons.folder_off_outlined
          : Icons.cloud_off_outlined,
      title: firstPicLogin
          ? '请先登录 Pic'
          : auth
          ? '需要重新登录'
          : storage
          ? '文件暂不可用'
          : '暂时无法加载',
      message: auth
          ? '当前页面已保留。登录后点击重试继续。'
          : storage
          ? '请检查文件是否存在、剩余空间和目录授权，再重试。'
          : error is ApiException
          ? '$error'
          : '请检查连接后重试；若持续失败，可稍后再试。',
      action: Wrap(
        spacing: 8,
        children: [
          if (auth && session != null)
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LoginScreen(session: session!),
                ),
              ),
              child: AppText(firstPicLogin ? '登录' : '重新登录'),
            ),
          FilledButton.tonal(onPressed: retry, child: const AppText('重试')),
        ],
      ),
    );
  }
}
