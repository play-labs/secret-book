import 'package:flutter/material.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF121A22),
              Color(0xFF18362E),
              Color(0xFFEEE7D8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = constraints.maxWidth < 980
                  ? constraints.maxWidth - 48
                  : 360.0;
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.85, -0.75),
                          radius: 1.1,
                          colors: [
                            Colors.white.withValues(alpha: 0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(40, 40, 40, 192),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Secret Book',
                              style: Theme.of(context)
                                  .textTheme
                                  .displayMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.4,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color: const Color(0xFFF6F2E8),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              subtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFFC9D7D0),
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 28),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBF4),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1A000000),
                                    blurRadius: 28,
                                    offset: Offset(0, 18),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: child,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: IgnorePointer(
                      ignoring: true,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: panelWidth,
                          minWidth: panelWidth.clamp(300.0, 360.0),
                        ),
                        child: const _VaultStatusPanel(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _VaultStatusPanel extends StatelessWidget {
  const _VaultStatusPanel();

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFFEADAA2);
    const panelColor = Color(0xFF161F28);
    const textColor = Color(0xFFF8F2E6);
    const mono = 'Cascadia Mono';

    return Container(
      decoration: BoxDecoration(
        color: panelColor,
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 5)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: textColor,
          fontFamily: mono,
          fontFamilyFallback: [
            'Microsoft YaHei',
            'Microsoft JhengHei UI',
            'Segoe UI'
          ],
          fontSize: 14,
          height: 1.3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _VaultHeader(),
            SizedBox(height: 10),
            _VaultMeterSection(),
            SizedBox(height: 10),
            Divider(color: Color(0xFFEADAA2), thickness: 1),
            SizedBox(height: 10),
            _VaultInfoSection(),
            SizedBox(height: 10),
            Divider(color: Color(0xFFEADAA2), thickness: 1),
            SizedBox(height: 10),
            _VaultHintSection(),
          ],
        ),
      ),
    );
  }
}

class _VaultHeader extends StatelessWidget {
  const _VaultHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: Divider(color: Color(0xFFEADAA2), thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'VAULT LOCKED',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFEADAA2), thickness: 1)),
      ],
    );
  }
}

class _VaultMeterSection extends StatelessWidget {
  const _VaultMeterSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _PanelRow(label: 'ENCRYPTION', meter: '██████████████', value: '100%'),
        SizedBox(height: 4),
        _PanelRow(label: 'KEY_BACKUP', meter: '', value: 'NONE'),
        SizedBox(height: 4),
        _PanelRow(label: 'RECOVERY', meter: '', value: 'NONE'),
      ],
    );
  }
}

class _VaultInfoSection extends StatelessWidget {
  const _VaultInfoSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(left: 'ONLY KEY', right: 'Your Password'),
        SizedBox(height: 2),
        _InfoRow(left: 'WHO KNOWS', right: 'Only You'),
        SizedBox(height: 2),
        _InfoRow(left: 'LOST KEY', right: '/dev/null'),
      ],
    );
  }
}

class _VaultHintSection extends StatelessWidget {
  const _VaultHintSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x441E2932),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '> 你的密码是解开一切唯一的钥匙',
            style: TextStyle(
                color: Color(0xFFF2F6F3), fontSize: 12.5, height: 1.2),
          ),
          SizedBox(height: 4),
          Text(
            '> 你的密码只有你知道',
            style: TextStyle(
                color: Color(0xFFF2F6F3), fontSize: 12.5, height: 1.2),
          ),
          SizedBox(height: 4),
          Text(
            '> _ ',
            style: TextStyle(
                color: Color(0xFFF2F6F3), fontSize: 12.5, height: 1.2),
          ),
        ],
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.label,
    required this.meter,
    required this.value,
  });

  final String label;
  final String meter;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 106,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(
          width: 18,
          child: Text('[', textAlign: TextAlign.center),
        ),
        SizedBox(
          width: 120,
          child: Text(meter,
              textAlign: TextAlign.left, overflow: TextOverflow.clip),
        ),
        const SizedBox(
          width: 18,
          child: Text(']', textAlign: TextAlign.center),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 52,
          child: Text(value, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 94,
          child:
              Text(left, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(
          width: 34,
          child: Text('->', textAlign: TextAlign.center),
        ),
        Expanded(child: Text(right)),
      ],
    );
  }
}
