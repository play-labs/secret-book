class VaultKdfSettings {
  const VaultKdfSettings({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  int get memoryMiB => (memoryKiB / 1024).round();

  String get technicalLabel => '${memoryMiB}M + $iterations + $parallelism';

  @override
  bool operator ==(Object other) {
    return other is VaultKdfSettings &&
        other.memoryKiB == memoryKiB &&
        other.iterations == iterations &&
        other.parallelism == parallelism;
  }

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);
}

enum EncryptionProfile {
  light(
    memoryKiB: 65536,
    iterations: 3,
    parallelism: 1,
    label: '[\u8f7b\u5feb]',
  ),
  standard(
    memoryKiB: 131072,
    iterations: 3,
    parallelism: 1,
    label: '[\u666e\u901a(\u9ed8\u8ba4)]',
  ),
  strong(
    memoryKiB: 131072,
    iterations: 4,
    parallelism: 1,
    label: '[\u5f3a\u4e00\u70b9]',
  ),
  slowest(
    memoryKiB: 262144,
    iterations: 4,
    parallelism: 1,
    label: '[\u66f4\u5f3a\u4e86,\u4e5f\u6162\u4e86]',
  );

  const EncryptionProfile({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.label,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final String label;

  VaultKdfSettings get settings => VaultKdfSettings(
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
      );

  String get displayLabel => '${settings.memoryMiB}M + $iterations\u8f6e + $parallelism $label';

  static EncryptionProfile? fromSettings(VaultKdfSettings settings) {
    for (final profile in EncryptionProfile.values) {
      if (profile.memoryKiB == settings.memoryKiB &&
          profile.iterations == settings.iterations &&
          profile.parallelism == settings.parallelism) {
        return profile;
      }
    }
    return null;
  }
}
