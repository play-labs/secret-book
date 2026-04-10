import 'package:flutter/material.dart';

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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF16372D),
              Color(0xFF284E45),
              Color(0xFFEFE7D8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 16,
              color: const Color(0xFFFFFBF4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('创建主密码', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Text('当前用户：${widget.username}', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('这个用户还没有本地保险库。设置主密码后将创建并加密 ${widget.username}/vault.bundle。', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
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
                    Text('请妥善保管主密码。当前版本没有找回密码能力，遗忘后将无法解密已有数据。', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(_isSubmitting ? '正在创建...' : '创建并进入'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _isSubmitting ? null : widget.onChangeUser, child: const Text('切换用户')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}