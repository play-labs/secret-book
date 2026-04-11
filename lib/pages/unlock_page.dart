import 'package:flutter/material.dart';

import 'auth_scaffold.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({
    super.key,
    required this.username,
    required this.onUnlock,
    required this.onChangeUser,
  });

  final String username;
  final Future<void> Function(String password) onUnlock;
  final VoidCallback onChangeUser;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await widget.onUnlock(_passwordController.text);
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
      title: '解锁保险库',
      subtitle: '输入主密码以解锁这个用户的保险库。你的密码不会以明文形式保存，它只是当前会话里开启加密数据的唯一钥匙。',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.username,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '输入主密码以解锁当前用户的 Secret Book。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF5E6E68),
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _passwordController,
            obscureText: _obscureText,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '主密码',
              errorText: _errorText,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureText = !_obscureText),
                icon: Icon(_obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_isSubmitting ? '正在解锁...' : '解锁'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isSubmitting ? null : widget.onChangeUser,
            child: const Text('切换用户'),
          ),
        ],
      ),
    );
  }
}
