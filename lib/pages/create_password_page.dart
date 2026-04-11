import 'package:flutter/material.dart';

import 'auth_scaffold.dart';

class CreatePasswordPage extends StatefulWidget {
  const CreatePasswordPage({
    super.key,
    required this.username,
    required this.onCreatePassword,
    required this.onChangeUser,
  });

  final String username;
  final Future<void> Function(String password) onCreatePassword;
  final VoidCallback onChangeUser;

  @override
  State<CreatePasswordPage> createState() => _CreatePasswordPageState();
}

class _CreatePasswordPageState extends State<CreatePasswordPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password.trim().isEmpty) {
      setState(() => _errorText = '请输入主密码');
      return;
    }
    if (password.length < 8) {
      setState(() => _errorText = '主密码至少需要 8 个字符');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorText = '两次输入的密码不一致');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await widget.onCreatePassword(password);
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
      title: '创建主密码',
      subtitle: '这个用户还没有本地保险库。设置主密码后将创建并加密对应用户的 vault.bundle。遗失密码后，当前版本没有找回能力。',
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
            '为这个用户创建唯一的主密码。之后每次解锁都需要它。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF5E6E68),
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '主密码',
              errorText: _errorText,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '确认主密码',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '请妥善保管主密码。它不会以明文形式保存，你遗失后也无法由程序替你恢复。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5E6E68),
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_isSubmitting ? '正在创建...' : '创建并进入'),
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
