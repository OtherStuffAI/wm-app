import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/local_flight_deck_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flightDeckServer = await LocalFlightDeckServer.start();
  runApp(WingmanApp(localFlightDeckUrl: flightDeckServer.url));
}
