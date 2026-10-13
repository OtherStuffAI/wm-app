import 'flight_deck_update_models.dart';

class LocalFlightDeckServer {
  static const origin = '';

  static Future<LocalFlightDeckServer> start({
    FlightDeckUpdateController? updates,
    String assetPrefix = 'assets/flightdeck/',
    int serverPort = 47831,
  }) async {
    return LocalFlightDeckServer();
  }

  String get url => '';
}
