import 'package:flutter/widgets.dart';

/// Navigator global de la app. Permite abrir overlays/hojas (p. ej. los
/// controles del mini-control de casting) desde el `builder` de MaterialApp,
/// que está por encima del Navigator y no tiene uno en su árbol local.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
