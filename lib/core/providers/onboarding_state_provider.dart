import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding step identifiers.
///
/// Persisted across cold starts in SharedPreferences (`onboarding_step` int).
/// The Splash screen consults this to resume the user mid-flow if the app
/// was killed between OTP verify and onboarding completion.
enum OnboardingStep {
  /// Family record not yet created. Splash routes here after a successful
  /// OTP for a new auth user.
  familyName('/onboarding/family-name'),

  /// Family row exists but child decision not yet made (the screen with
  /// the cafe-only escape).
  addChild('/onboarding/add-child'),

  /// Add-child chosen; collecting the child's details.
  childDetails('/onboarding/child-details'),

  /// Child created; picking favourite hero.
  heroPick('/onboarding/hero-pick'),

  /// Onboarding complete (cafe-only path or post-hero-pick).
  complete('/home');

  const OnboardingStep(this.route);
  final String route;

  // The persisted int matches the enum's declaration order via the built-in
  // `index` getter. Don't reorder enum values without a migration of stored
  // SharedPreferences ints.
  static OnboardingStep fromIndex(int? i) {
    if (i == null || i < 0 || i >= OnboardingStep.values.length) {
      return OnboardingStep.familyName;
    }
    return OnboardingStep.values[i];
  }
}

/// SharedPreferences-backed onboarding step. Read once at splash, written
/// at the end of each onboarding screen.
final onboardingStepProvider =
    AsyncNotifierProvider<OnboardingStepController, OnboardingStep>(
  OnboardingStepController.new,
);

class OnboardingStepController extends AsyncNotifier<OnboardingStep> {
  static const _key = 'onboarding_step';
  static const _completeKey = 'onboarding_complete';
  static const _childIdKey = 'onboarding_child_id';

  @override
  Future<OnboardingStep> build() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_completeKey) == true) return OnboardingStep.complete;
    return OnboardingStep.fromIndex(prefs.getInt(_key));
  }

  Future<void> setStep(OnboardingStep step) async {
    final prefs = await SharedPreferences.getInstance();
    if (step == OnboardingStep.complete) {
      await prefs.setBool(_completeKey, true);
      await prefs.remove(_key);
    } else {
      await prefs.setInt(_key, step.index);
      await prefs.remove(_completeKey);
    }
    state = AsyncValue.data(step);
  }

  /// Wipe everything — used on sign-out and after an onboarding hard-reset.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_completeKey);
    await prefs.remove(_childIdKey);
    state = const AsyncValue.data(OnboardingStep.familyName);
  }
}

/// Whether the user has already seen the Welcome Manifesto screen (the
/// "Brave. Kind. Curious. Creative." intro shown right after first OTP
/// verify). Persists across reinstalls of the app only as long as the
/// device's SharedPreferences survive — fine for v1.
final hasSeenWelcomeManifestoProvider =
    AsyncNotifierProvider<HasSeenWelcomeManifestoController, bool>(
  HasSeenWelcomeManifestoController.new,
);

class HasSeenWelcomeManifestoController extends AsyncNotifier<bool> {
  static const _key = 'has_seen_welcome_manifesto';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    state = const AsyncValue.data(true);
  }
}

/// The child UUID created during onboarding, used by the hero-pick step
/// to know which child to update. Stored in SharedPreferences so it
/// survives an app kill between child-details and hero-pick.
final currentOnboardingChildIdProvider =
    AsyncNotifierProvider<OnboardingChildIdController, String?>(
  OnboardingChildIdController.new,
);

class OnboardingChildIdController extends AsyncNotifier<String?> {
  static const _key = 'onboarding_child_id';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> set(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, id);
    }
    state = AsyncValue.data(id);
  }
}
