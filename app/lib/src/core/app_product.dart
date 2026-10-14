/// Compile-time product selection; service authority is never selected here.
class AppProduct {
  static const ambulando =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'ambulando';
  static const title = ambulando ? 'Ambulando' : 'Nostr Browser';
  static const bundledTitle = ambulando ? 'Ambulando' : 'Flight Deck';
  static const assetPrefix =
      ambulando ? 'assets/ambulando/' : 'assets/flightdeck/';
  static const localPort = ambulando ? 47832 : 47831;
}
