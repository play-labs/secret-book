import 'package:flutter/material.dart';

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
            constraints: const BoxConstraints(maxWidth: 460),
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
                    Text('解锁 Secret Book', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Text('当前用户：${widget.username}', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('输入主密码以解锁这个用户的保险库。', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
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