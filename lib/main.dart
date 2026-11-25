import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'simple_purchases_controller.dart';
import 'storekit/storekit_bridge.dart';
import 'team_subscription_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final team = TeamSubscriptionController(bridge: StoreKitBridge())..start();
  final oneTime = SimplePurchasesController(
    // A team plan renewal can also reach the plugin's purchase stream.
    onOtherTransaction: team.refreshEntitlements,
  )..start();
  runApp(TeamSubscriptionApp(team: team, oneTime: oneTime));
}

class TeamSubscriptionApp extends StatelessWidget {
  const TeamSubscriptionApp({
    super.key,
    required this.team,
    required this.oneTime,
  });

  final TeamSubscriptionController team;
  final SimplePurchasesController oneTime;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Team Subscriptions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(team: team, oneTime: oneTime),
    );
  }
}
