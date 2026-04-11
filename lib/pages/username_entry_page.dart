import 'package:flutter/material.dart';

import 'auth_scaffold.dart';

class UsernameEntryPage extends StatefulWidget {
  const UsernameEntryPage({
    super.key,
    required this.onContinue,
  });

  final Future<void> Function(String username) onContinue;

  @override
  State<UsernameEntryPage> createState() => _UsernameEntryPageState();
}

class _UsernameEntryPageState extends State<UsernameEntryPage> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _errorText = '请输入用户名';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await widget.onContinue(username);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: '输入用户名',
      subtitle: '用户名会决定本地保险库目录，以及 OSS 上的保存路径。先选中身份，再解锁属于这个用户的保险库。',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '欢迎回来',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Secret Book 会按用户名隔离本地 vault 和远端同步路径。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF5E6E68),
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _usernameController,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '用户名',
              hintText: '例如：alice',
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_isSubmitting ? '正在继续...' : '继续'),
            ),
          ),
        ],
      ),
    );
  }
}
