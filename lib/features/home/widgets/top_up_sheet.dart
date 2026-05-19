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
  // Server diagnostic echoed back by razorpay-topup v13. Stored so the
  // error handler can surface the server's actual RAZORPAY_MODE / key
  // prefix alongside the SDK error code — that's how we'll know whether
  // a "code 1" failure is really a client/server key-pair mismatch.
  String? _serverMode;
  String? _serverKeyPrefix;
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
    // Hard re-entrancy guard. Setting `_stage = processing` hides the
    // Pay button on the next rebuild, but a fast double-tap can fire
    // _initiatePayment twice in the same frame and create two Razorpay
    // orders (with two distinct idempotency keys, so the server can't
    // dedupe them). Bail immediately if we're already mid-flight.
    if (_stage != _SheetStage.picking) return;

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
      _serverMode = data['server_mode'] as String?;
      _serverKeyPrefix = data['server_key_prefix'] as String?;
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
        return;
      }
      // Confirmed — now start the polling fallback (in case Realtime
      // misses the wallet_transactions insert).
      if (_idempotencyKey != null) _startCreditPolling(_idempotencyKey!);
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
      'name': 'Play Diaries',
      'description': 'Wallet top-up',
      'prefill': {
        'contact': family?['phone'] ?? '',
      },
      'notes': {
        'family_id': family?['id'],
        'idempotency_key': _idempotencyKey,
      },
      'theme': {'color': '#1E3A7B'},
      // Show GPay / PhonePe / Paytm app icons that deep-link into the
      // app for one-tap pay. Requires LSApplicationQueriesSchemes in
      // Info.plist (added 2026-05-19) — without it Razorpay's iOS SDK
      // can't probe canOpenURL and silently falls back to the collect
      // flow ("Pay with UPI ID").
      //
      // The earlier attempt to use this `apps` shape failed with
      // "Uh! oh!" because the Info.plist whitelist was missing. With
      // the schemes whitelisted, Razorpay returns the app-icon block
      // and the order is accepted.
      'config': {
        'display': {
          'blocks': {
            'upi': {
              'name': 'Pay using a UPI app',
              'instruments': [
                {
                  'method': 'upi',
                  'flows': ['intent'],
                  'apps': ['google_pay', 'phonepe', 'paytm'],
                },
              ],
            },
            'other': {
              'name': 'Other Payment methods',
              'instruments': [
                {'method': 'card'},
                {'method': 'netbanking'},
                {'method': 'wallet'},
                {
                  'method': 'upi',
                  'flows': ['collect', 'qr'],
                },
              ],
            },
          },
          'sequence': ['block.upi', 'block.other'],
          'preferences': {'show_default_blocks': false},
        },
      },
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
        return;
      }
      // Server has confirmed the payment — the wallet_topup RPC should
      // insert the wallet_transactions row within ~1s. Start the polling
      // fallback now (NOT at order-create time) so the 56-second budget
      // is spent waiting for the credit, not for the parent to finish
      // typing card / OTP on the Razorpay sheet.
      if (_idempotencyKey != null) _startCreditPolling(_idempotencyKey!);
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
    // Surface the actual code + message in the UI so we can diagnose
    // why the Razorpay sheet failed (key mismatch, amount issue, etc.).
    // Generic "Payment failed" hides the cause and led to a whole
    // diagnostic detour 2026-05-19.
    final code = res.code;
    final msg  = res.message ?? 'Payment failed.';
    // Append the server diag echoed by v13 + the client key prefix. If
    // server is in test mode with rzp_test_* but the client opened the
    // sheet with a rzp_live_* key (or vice-versa), Razorpay rejects the
    // order with code 1 (INVALID_OPTIONS) — and this single snackbar
    // line makes that mismatch obvious.
    final cliPrefix = F.razorpayKeyId.isNotEmpty
        ? F.razorpayKeyId.substring(0, F.razorpayKeyId.length < 8 ? F.razorpayKeyId.length : 8)
        : '(empty)';
    final diagSuffix =
        ' [srv=${_serverMode ?? "?"}/${_serverKeyPrefix ?? "?"} cli=$cliPrefix]';
    _failProcessing('$msg (code $code)$diagSuffix');
  }

  void _onExternalWallet(ExternalWalletResponse res) {
    // External wallet selected (e.g., Paytm). Razorpay will fire
    // payment_success or payment_error after the user completes — no extra
    // handling needed here.
  }

  // ---------------------------------------------------------------------
  //  Wallet Realtime listener — drives transition to success.
  //
  //  We arm the Realtime listener as soon as the Razorpay order is
  //  created (so we never miss the wallet_transactions insert), but we
  //  DON'T start the polling fallback until payment is actually
  //  confirmed. The polling timeout was previously firing while parents
  //  were still on the Razorpay authorize screen — by the time they
  //  finished and the credit hit, our 56-second timer had already
  //  expired and cancelled the listener, leaving the sheet stuck on
  //  "Took longer than expected." even though the wallet was funded.
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
  }

  /// Kick off the progressive polling fallback. Called *after* Razorpay
  /// (or mock) confirms payment — not before — so the 56s budget is
  /// spent waiting for the wallet row, not for the parent to finish
  /// typing card / OTP details on Razorpay.
  void _startCreditPolling(String idem) {
    _txTimeout?.cancel();
    _schedulePollForCreditRow(idem, attempt: 0);
  }

  void _schedulePollForCreditRow(String idem, {required int attempt}) {
    final delay = attempt == 0
        ? const Duration(seconds: 8)
        : const Duration(seconds: 3);
    _txTimeout = Timer(delay, () => _pollForCreditRow(idem, attempt: attempt));
  }

  Future<void> _pollForCreditRow(String idem, {required int attempt}) async {
    if (!mounted || _stage != _SheetStage.processing) return;
    try {
      final rows = await Supabase.instance.client
          .from('wallet_transactions')
          .select('id')
          .eq('idempotency_key', idem)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        _markSuccess();
        return;
      }
    } catch (_) {
      // Network blip — fall through to retry/give-up logic.
    }
    if (attempt < 17) {
      _schedulePollForCreditRow(idem, attempt: attempt + 1);
    } else {
      _failProcessing(
        'Took longer than expected. The credit will appear shortly.',
      );
    }
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

    final canPay = _selectedAmountPaise != null;
    final payLabel = canPay
        ? 'Pay ${Money.fromPaise(_selectedAmountPaise!)}'
        : 'Choose an amount';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Bottom padding mirrors the keyboard inset so the sticky Pay
      // footer (rendered below) lifts above the keypad instead of
      // hiding behind it. Without this, parents had to scroll the
      // sheet to find the Pay button after typing a custom amount.
      padding: EdgeInsets.only(
        top: 12,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom,
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
          // Scrollable body — picks up only the part of the sheet that
          // *needs* to scroll, so the Pay footer below stays pinned
          // even when the keyboard is up.
          Flexible(
            child: SingleChildScrollView(
              child: _stage == _SheetStage.success
                  ? _SuccessView(
                      totalPaise: (_selectedAmountPaise ?? 0) +
                          (_selectedBonusPaise ?? 0),
                    )
                  : _stage == _SheetStage.processing
                      ? const _ProcessingView()
                      : _PickingBody(
                          offers: offers,
                          balancePaise: balance,
                          selectedAmountPaise: _selectedAmountPaise,
                          selectedBonusPaise: _selectedBonusPaise,
                          customController: _customController,
                          errorText: _errorText,
                          onSelectQuick: _selectQuick,
                          onCustomChanged: _customAmountChanged,
                        ),
            ),
          ),
          if (_stage == _SheetStage.picking) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: payLabel,
                onPressed: canPay ? _initiatePayment : null,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Secure payment by Razorpay',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Picking body — everything that scrolls. The Pay button + Razorpay
//  caption live in the sheet's pinned footer, not here, so the CTA
//  stays visible above the keyboard while a parent types a custom
//  amount.
// ---------------------------------------------------------------------------
class _PickingBody extends StatelessWidget {
  final List<dynamic> offers;
  final int? balancePaise;
  final int? selectedAmountPaise;
  final int? selectedBonusPaise;
  final TextEditingController customController;
  final String? errorText;
  final void Function(int amount, int bonus) onSelectQuick;
  final ValueChanged<String> onCustomChanged;

  const _PickingBody({
    required this.offers,
    required this.balancePaise,
    required this.selectedAmountPaise,
    required this.selectedBonusPaise,
    required this.customController,
    required this.errorText,
    required this.onSelectQuick,
    required this.onCustomChanged,
  });

  @override
  Widget build(BuildContext context) {
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
