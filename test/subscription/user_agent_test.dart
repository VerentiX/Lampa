import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/subscription/user_agent.dart';

void main() {
  test('Lampa worker receives exact sing-box selector UA', () {
    expect(buildSubscriptionUserAgent(appVersion: '1.5.1'), 'Lampa-Mobile-SB');
    expect(buildSubscriptionUserAgent(appVersion: ''), 'Lampa-Mobile-SB');
  });

  test('stale Lampa UAs are detected for /auto heal', () {
    expect(isStaleLampaSubscriptionUa('Lampa-Subscription'), isTrue);
    expect(isStaleLampaSubscriptionUa('Lampa-Mobile/1.4.0'), isTrue);
    expect(isStaleLampaSubscriptionUa('Lampa-Mobile'), isTrue);
    expect(isStaleLampaSubscriptionUa('LxBox-android/2.0.4'), isTrue);
    expect(isStaleLampaSubscriptionUa('Lampa-Mobile-SB'), isFalse);
    expect(isStaleLampaSubscriptionUa(''), isFalse);
  });
}
