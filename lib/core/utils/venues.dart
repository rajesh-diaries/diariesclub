/// Centralised venue identifiers. Avoids repeating UUID literals across
/// the customer / admin / staff flavors. When multi-venue support
/// arrives, swap the call sites that read this constant for a
/// `currentVenueIdProvider` that resolves from family / staff context.
class Venues {
  Venues._();

  /// Kondapur, Hyderabad — the only live venue today.
  static const String kondapurId = '00000000-0000-0000-0000-000000000001';
}
