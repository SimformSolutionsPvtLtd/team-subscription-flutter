import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config.dart';
import '../simple_purchases_controller.dart';
import '../widgets/notice.dart';

/// The one-time purchases tab: a consumable and a non-consumable, bought
/// through the `in_app_purchase` plugin.
class OneTimePurchasesView extends StatelessWidget {
  const OneTimePurchasesView({super.key, required this.controller});

  final SimplePurchasesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _body(context),
  );

  Widget _body(BuildContext context) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!controller.isStoreAvailable) {
      return const Notice(
        icon: Icons.storefront_outlined,
        title: 'App Store unavailable',
        body: 'In-app purchases are turned off on this device.',
      );
    }
    final text = Theme.of(context).textTheme;
    final coins = controller.coins;
    final pro = controller.proUnlock;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'These use the in_app_purchase plugin, because they need no '
              'seats. Team plans need seats(_:), which the plugin can\'t '
              'pass, so they go through the app\'s StoreKit bridge.',
              style: text.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (coins == null && pro == null)
          const Notice(
            icon: Icons.inventory_2_outlined,
            title: 'No products found',
            body:
                'StoreKit returned neither COINS_PRODUCT_ID nor '
                'PRO_UNLOCK_PRODUCT_ID from config.json.',
          ),
        if (coins != null)
          _ProductCard(
            product: coins,
            kind: 'Consumable',
            status: 'You have ${controller.coinBalance} coins',
            buttonLabel: 'Buy $coinsPerPurchase coins',
            isBusy: controller.busyProductId == coins.id,
            onBuy: controller.busyProductId == null
                ? controller.buyCoins
                : null,
          ),
        if (pro != null)
          _ProductCard(
            product: pro,
            kind: 'Non-consumable',
            status: controller.ownsPro ? 'Owned' : 'Not owned',
            buttonLabel: controller.ownsPro ? 'Owned' : 'Unlock',
            isBusy: controller.busyProductId == pro.id,
            onBuy: controller.ownsPro || controller.busyProductId != null
                ? null
                : controller.buyProUnlock,
          ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.kind,
    required this.status,
    required this.buttonLabel,
    required this.isBusy,
    required this.onBuy,
  });

  final ProductDetails product;
  final String kind;
  final String status;
  final String buttonLabel;
  final bool isBusy;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.title.isEmpty ? product.id : product.title,
                      style: text.titleMedium,
                    ),
                  ),
                  Text(product.price, style: text.titleMedium),
                ],
              ),
              Text(kind, style: text.bodySmall),
              if (product.description.isNotEmpty) Text(product.description),
              const SizedBox(height: 8),
              Text(status),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onBuy,
                  child: isBusy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
