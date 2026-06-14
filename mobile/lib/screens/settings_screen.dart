import 'package:flutter/material.dart';
import '../core/app_version.dart';
import 'update_log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('设置', style: textTheme.titleLarge),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: const Color(0xFF161B22),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          '关于',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '本应用独立运行，无需连接服务器。所有行情数据通过公开接口获取，技术分析在本地计算完成。',
                      style: textTheme.bodyMedium?.copyWith(color: Colors.grey[300]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFF161B22),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UpdateLogScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 24, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '更新日志',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '版本: v${AppVersion.version}',
              style: textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
