import 'package:flutter_test/flutter_test.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import 'package:q_pro/core/network/infrive_api.dart';
import 'package:q_pro/core/storage/outbox_sync.dart';
import 'package:q_pro/main.dart';

void main() {
  setUp(() {
    // main.dart's _ConnectivityBanner reads OutboxSync.instance on every
    // build; normally wired up in main(), which this test bypasses by
    // pumping QProApp directly. The banner never calls out over the
    // network just by rendering, so any InfriveApi/FrappeClient pair is
    // fine here — nothing in it actually gets exercised.
    OutboxSync.resetForTesting();
    OutboxSync.init(
      InfriveApi(FrappeClient('http://test.invalid/')),
      FrappeClient('http://test.invalid/'),
    );
  });

  testWidgets('Shows the login screen when not logged in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QProApp(startLoggedIn: false));

    expect(find.text('Q-Pro'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });
}
