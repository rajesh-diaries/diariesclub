import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/current_wallet_provider.dart';
import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../flavors.dart';

/// Modal sheet for wallet top-up. Quick-pick tiles (from
/// venue_config.topup_offers) + a custom amount. Drives the razorpay-topup
/// Edge Function end-to-end:
///
///   1. POST { action: "create_order", amount_paise, bonus_paise, idem }
///        → { order_id, mock? }
///   2a. mock=true  → POST confirm immediately (no Razorpay sheet).
///   2b. mock=false → razorpay.open(order_id); on payment_success →
///        POST { action: "confirm", order_id, payment_id, signature, idem }.
///   3. Wait for the matching wallet_transactions row to appear via the
///      `wallet_transactions` Realtime stream (idempotency_key match), then
///      flip to success and dismiss with a toast.
class TopUpSheet extends ConsumerStatefulWidget {
  const TopUpSheet({super.key});

  @override
  ConsumerState<TopUpSheet> createState() => _TopUpSheetState();
}

enum _SheetStage { picking, processing, success }

class _TopUpSheetState extends ConsumerState<TopUpSheet> {
  late final Razorpay _razorpay;
  final _customController = TextEditingController();

  int? _selectedAmountPaise;
  int? _selectedBonusPaise;
  _SheetStage _stage = _SheetStage.picking;
  String? _errorText;
  String? _idempotencyKey;
  String? _orderId;
  StreamSubscription<List<Map<String, dynamic>>>? _txSub;
  Timer? _txTimeout;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    _customController.dispose();
    _txSub?.cancel();
    _txTimeout?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  //  Selection
  // ---------------------------------------------------------------------
  void _selectQuick(int amount, int bonus) {
    setState(() {
      _selectedAmountPaise = amount;
      _selectedBonusPaise = bonus;
      _customController.clear();
      _errorText = null;
    });
  }

  void _customAmountChanged(String raw) {
    final rupees = int.tryParse(raw);
    setState(() {
      _errorText = null;
      if (rupees == null) {
        _selectedAmountPaise = null;
        _selectedBonusPaise = null;
        return;
      }
      // Hard floor/ceiling — same as Edge Function.
      if (rupees < 1 || rupees > 50000) {
        _selectedAmountPaise = null;
        _selectedBonusPaise = null;
        return;
      }
      _selectedAmountPaise = rupees * 100;
      _selectedBonusPaise = 0;
    });
  }

  // ---------------------------------------------------------------------
  //  Flow
  // ---------------------------------------------------------------------
  Future<void> _initiatePayment() async {
    if (_selectedAmountPaise == null) return;

    setState(() {
      _stage = _SheetStage.processing;
      _errorText = null;
    });
    final idem = const Uuid().v4();
    _idempotencyKey = idem;

    Sentry.addBreadcrumb(Breadcrumb(
      category: 'razorpay',
      type: 'user',
      level: SentryLevel.info,
      message: 'create_order initiate',
      data: {
        'amount_paise': _selectedAmountPaise,
        'bonus_paise': _selectedBonusPaise ?? 0,
        'mock_mode': F.isMockRazorpay,
      },
    ));

    try {
      // 1) Ask the Edge Function to create an order.
      final res = await Supabase.instance.client.functions.invoke(
        'razorpay-topup',
        body: {
          'action': 'create_order',
          'amount_paise': _selectedAmountPaise,
          'bonus_paise': _selectedBonusPaise ?? 0,
          'idempotency_key': idem,
        },
      );

      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true) {
        Sentry.addBreadcrumb(Breadcrumb(
          category: 'razorpay',
          level: SentryLevel.warning,
          message: 'create_order rejected',
          data: {'error': data['error']},
        ));
        _failProcessing(_mapError(data['error'] as String?));
        return;
      }

      _orderId = data['order_id'] as String?;
      final mock = data['mock'] == true || F.isMockRazorpay;
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'razorpay',
        level: SentryLevel.info,
        message: 'create_order ok',
        data: {'mock': mock},
      ));

      // Subscribe to wallet_transactions BEFORE confirming — this way we
      // never miss a row inserted between confirm() and the listener.
      _listenForCreditRow(idem);

      if (mock) {
        // Skip Razorpay sheet entirely.
        await _confirmMock();
      } else {
        _openRazorpay();
      }
    } on FunctionException catch (e, st) {
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('integration', 'razorpay');
        scope.setTag('step', 'create_order');
      });
      _failProcessing(_mapError(e.details?.toString()));
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('integration', 'razorpay');
        scope.setTag('step', 'create_order_unknown');
      });
      _failProcessing("Couldn't reach the server. Please try again.");
    }
  }

  Future<void> _confirmMock() async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'razorpay-topup',
        body: {
          'action': 'confirm',
          'order_id': _orderId,
          'payment_id': 'mock_pay_${const Uuid().v4()}',
          'signature': '',
          'amount_paise': _selectedAmountPaise,
          'bonus_paise': _selectedBonusPaise ?? 0,
          'idempotency_key': _idempotencyKey,
        },
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true) {
        _failProcessing(_mapError(data['error'] as String?));
      }
      // If ok, the wallet_transactions listener will flip the stage.
    } catch (_) {
      _failProcessing("Couldn't credit wallet. Please try again.");
    }
  }

  void _openRazorpay() {
    final family = ref.read(currentFamilyProvider).valueOrNull;
    final options = <String, dynamic>{
      'key': F.razorpayKeyId,
      'amount': _selectedAmountPaise,
      'order_id': _orderId,
      'name': 'Diaries Club',
      'description': 'Wallet top-up',
      'prefill': {
        'contact': family?['phone'] ?? '',
        'email': family?['email'] ?? '',
      },
      'notes': {
        'family_id': family?['id'],
        'idempotency_key': _idempotencyKey,
      },
      'theme': {'color': '#1E3A7B'},
    };
    try {
      _razorpay.open(options);
    } catch (_) {
      _failProcessing("Couldn't open the payment sheet. Please try again.");
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse res) async {
    Sentry.addBreadcrumb(Breadcrumb(
      category: 'razorpay',
      level: SentryLevel.info,
      message: 'sheet success',
      // Don't log payment_id — Razorpay's id is not PII but tying our
      // logs to it offers little debug value vs. the idempotency_key
      // that's already in the create_order breadcrumb.
      data: {'has_signature': res.signature?.isNotEmpty ?? false},
    ));
    try {
      final result = await Supabase.instance.client.functions.invoke(
        'razorpay-topup',
        body: {
          'action': 'confirm',
          'order_id': _orderId,
          'payment_id': res.paymentId,
          'signature': res.signature,
          'idempotency_key': _idempotencyKey,
        },
      );
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true) {
        Sentry.addBreadcrumb(Breadcrumb(
          category: 'razorpay',
          level: SentryLevel.error,
          message: 'confirm rejected',
          data: {'error': data['error']},
        ));
        _failProcessing(_mapError(data['error'] as String?));
      }
      // The wallet_transactions listener handles success.
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st, withScope: (scope) {
        scope.setTag('integration', 'razorpay');
        scope.setTag('step', 'confirm');
        // Reconciliation cron (Session 13) backfills wallet credit if
        // the webhook arrives but we miss this confirm; surface that
        // expectation in the UI.
      });
      _failProcessing(
        "Payment received but couldn't credit wallet. It will appear shortly.",
      );
    }
  }

  void _onPaymentError(PaymentFailureResponse res) {
    // Razorpay error codes: BAD_REQUEST_ERROR (user cancelled),
    // GATEWAY_ERROR, NETWORK_ERROR, SERVER_ERROR. Most are user-side; we
    // log them as breadcrumb, not exception, to avoid Sentry noise.
    Sentry.addBreadcrumb(Breadcrumb(
      category: 'razorpay',
      level: SentryLevel.warning,
      message: 'sheet failure',
      data: {'code': res.code, 'message': res.message},
    ));
    _failProcessing(res.message ?? 'Payment failed.');
  }

  void _onExternalWallet(ExternalWalletResponse res) {
    // External wallet selected (e.g., Paytm). Razorpay will fire
    // payment_success or payment_error after the user completes — no extra
    // handling needed here.
  }

  // ---------------------------------------------------------------------
  //  Wallet Realtime listener — drives transition to success.
  // ---------------------------------------------------------------------
  void _listenForCreditRow(String idem) {
    _txSub?.cancel();
    _txTimeout?.cancel();

    final familyId = Supabase.instance.client.auth.currentUser?.id;
    if (familyId == null) return;

    final stream = Supabase.instance.client
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('created_at', ascending: false)
        .limit(10);

    _txSub = stream.listen((rows) {
      final hit = rows.firstWhere(
        (r) => r['idempotency_key'] == idem,
        orElse: () => <String, dynamic>{},
      );
      if (hit.isEmpty) return;
      _markSuccess();
    });

    // 30s safety net — if Realtime is wedged, fall back to polling once.
    _txTimeout = Timer(const Duration(seconds: 30), () async {
      if (_stage != _SheetStage.processing) return;
      final rows = await Supabase.instance.client
          .from('wallet_transactions')
          .select()
          .eq('idempotency_key', idem)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        _markSuccess();
      } else {
        _failProcessing(
          'Took longer than expected. The credit will appear shortly.',
        );
      }
    });
  }

  void _markSuccess() {
    if (!mounted || _stage != _SheetStage.processing) return;
    _txTimeout?.cancel();
    _txSub?.cancel();
    setState(() => _stage = _SheetStage.success);
    final total = (_selectedAmountPaise ?? 0) + (_selectedBonusPaise ?? 0);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text('${Money.fromPaise(total)} added to your wallet'),
        ),
      );
    });
  }

  void _failProcessing(String message) {
    if (!mounted) return;
    _txTimeout?.cancel();
    _txSub?.cancel();
    setState(() {
      _stage = _SheetStage.picking;
      _errorText = message;
    });
  }

  String _mapError(String? code) {
    switch (code) {
      case 'invalid_amount':
        return 'Please enter an amount between ₹1 and ₹50,000.';
      case 'invalid_signature':
        return 'Payment signature mismatch. Please try again.';
      case 'family_mismatch':
        return "Couldn't verify your account. Please sign in again.";
      case 'razorpay_create_failed':
      case 'razorpay_fetch_failed':
        return 'Payment service unavailable. Please try again in a moment.';
      case 'wallet_topup_failed':
        return "Couldn't credit your wallet. Please try again.";
      default:
        return "Couldn't process payment. Please try again.";
    }
  }

  // ---------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull;
    final offers = (cfg?['topup_offers'] as List?) ?? const [];
    final balance = ref.watch(walletBalancePaiseProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_stage == _SheetStage.success)
            _SuccessView(
              totalPaise:
                  (_selectedAmountPaise ?? 0) + (_selectedBonusPaise ?? 0),
            )
          else if (_stage == _SheetStage.processing)
            const _ProcessingView()
          else
            _PickingView(
              offers: offers,
              balancePaise: balance,
              selectedAmountPaise: _selectedAmountPaise,
              selectedBonusPaise: _selectedBonusPaise,
              customController: _customController,
              errorText: _errorText,
              onSelectQuick: _selectQuick,
              onCustomChanged: _customAmountChanged,
              onPay: _initiatePayment,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Picking view
// ---------------------------------------------------------------------------
class _PickingView extends StatelessWidget {
  final List<dynamic> offers;
  final int? balancePaise;
  final int? selectedAmountPaise;
  final int? selectedBonusPaise;
  final TextEditingController customController;
  final String? errorText;
  final void Function(int amount, int bonus) onSelectQuick;
  final ValueChanged<String> onCustomChanged;
  final VoidCallback onPay;

  const _PickingView({
    required this.offers,
    required this.balancePaise,
    required this.selectedAmountPaise,
    required this.selectedBonusPaise,
    required this.customController,
    required this.errorText,
    required this.onSelectQuick,
    required this.onCustomChanged,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final canPay = selectedAmountPaise != null;
    final payLabel = canPay
        ? 'Pay ${Money.fromPaise(selectedAmountPaise!)}'
        : 'Choose an amount';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Top up wallet', style: AppTextStyles.h2(context)),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
        if (balancePaise != null)
          Text(
            'Current balance: ${Money.fromPaise(balancePaise!)}',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        const SizedBox(height: 16),
        Text('Quick top-up', style: AppTextStyles.bodyLarge(context)),
        const SizedBox(height: 12),
        if (offers.isNotEmpty)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              for (final o in offers)
                _OfferTile(
                  amountPaise: (o['amount_paise'] as int?) ?? 0,
                  bonusPaise: (o['bonus_paise'] as int?) ?? 0,
                  badge: (o['badge'] as String?) ?? '',
                  label: (o['label'] as String?) ?? '',
                  selected: selectedAmountPaise ==
                          ((o['amount_paise'] as int?) ?? 0) &&
                      customController.text.isEmpty,
                  onTap: () => onSelectQuick(
                    (o['amount_paise'] as int?) ?? 0,
                    (o['bonus_paise'] as int?) ?? 0,
                  ),
                ),
            ],
          ),
        const SizedBox(height: 20),
        Text('Custom amount', style: AppTextStyles.bodyLarge(context)),
        const SizedBox(height: 8),
        TextField(
          controller: customController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onCustomChanged,
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: '1,500',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            helperText: 'Min ₹1, max ₹50,000',
          ),
          style: AppTextStyles.body(context),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: AppTextStyles.caption(context, color: AppColors.adminRed),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: payLabel,
            onPressed: canPay ? onPay : null,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Secure payment by Razorpay',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _OfferTile extends StatelessWidget {
  final int amountPaise;
  final int bonusPaise;
  final String badge;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OfferTile({
    required this.amountPaise,
    required this.bonusPaise,
    required this.badge,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.lightSurface,
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Money.fromPaise(amountPaise),
              style: AppTextStyles.h3(context),
            ),
            if (bonusPaise > 0)
              Text(
                '+${Money.fromPaise(bonusPaise)} bonus',
                style: AppTextStyles.caption(context, color: AppColors.gold),
              ),
            if (label.isNotEmpty)
              Text(
                badge.isEmpty ? label : '$badge $label',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Processing / Success
// ---------------------------------------------------------------------------
class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.navy),
          const SizedBox(height: 16),
          Text(
            'Crediting your wallet…',
            style: AppTextStyles.bodyLarge(context),
          ),
          const SizedBox(height: 4),
          Text(
            'This usually takes a couple of seconds.',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final int totalPaise;
  const _SuccessView({required this.totalPaise});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 64,
            color: AppColors.activeGreen,
          ),
          const SizedBox(height: 12),
          Text(
            '${Money.fromPaise(totalPaise)} added',
            style: AppTextStyles.h2(context),
          ),
        ],
      ),
    );
  }
}
