import 'dart:async';

import 'package:flutter/material.dart';

import '../simple_purchases_controller.dart';
import '../team_subscription_controller.dart';
import 'one_time_purchases_view.dart';
import 'plans_view.dart';

/// Two tabs: team plans (StoreKit bridge) and one-time purchases
/// (`in_app_purchase` plugin).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.team, required this.oneTime});

  final TeamSubscriptionController team;
  final SimplePurchasesController oneTime;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _subscriptions = <StreamSubscription<String>>[];
  var _tab = 0;
  var _restoring = false;

  @override
  void initState() {
    super.initState();
    for (final messages in [widget.team.messages, widget.oneTime.messages]) {
      _subscriptions.add(messages.listen(_showMessage));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    await widget.team.restorePurchases();
    await widget.oneTime.restorePurchases();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Team plans' : 'One-time purchases'),
        actions: [
          TextButton(
            onPressed: _restoring ? null : _restore,
            child: const Text('Restore'),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            PlansView(controller: widget.team),
            OneTimePurchasesView(controller: widget.oneTime),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Team plans',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: 'One-time',
          ),
        ],
      ),
    );
  }
}
