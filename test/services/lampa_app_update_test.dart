import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/lampa_app_update.dart';

void main() {
  const assets = <Map<String, String>>[
    {
      'name': 'Lampa_1.2.8-fdroid_arm64-v8a.apk',
      'browser_download_url': 'https://example/arm64.apk',
    },
    {
      'name': 'Lampa_1.2.8-fdroid_armeabi-v7a.apk',
      'browser_download_url': 'https://example/arm32.apk',
    },
    {
      'name': 'Lampa_1.2.8-fdroid_universal.apk',
      'browser_download_url': 'https://example/universal.apk',
    },
    {
      'name': 'Lampa_1.2.8-fdroid_x86.apk',
      'browser_download_url': 'https://example/x86.apk',
    },
    {
      'name': 'Lampa_1.2.8-fdroid_x86_64.apk',
      'browser_download_url': 'https://example/x64.apk',
    },
  ];

  test('selects APK matching the first supported Android ABI', () {
    expect(
      selectLampaApkAsset(assets, const ['arm64-v8a', 'armeabi-v7a']),
      'https://example/arm64.apk',
    );
    expect(
      selectLampaApkAsset(assets, const ['x86_64', 'x86']),
      'https://example/x64.apk',
    );
  });

  test('falls back to universal APK for an unknown ABI', () {
    expect(
      selectLampaApkAsset(assets, const ['riscv64']),
      'https://example/universal.apk',
    );
  });

  test('does not accept a non-APK release asset', () {
    expect(
      selectLampaApkAsset(
        const [
          {
            'name': 'checksums.txt',
            'browser_download_url': 'https://example/checksums.txt',
          },
        ],
        const ['arm64-v8a'],
      ),
      isNull,
    );
  });
}
