// Stub utilisé sur mobile — WebMic n'a aucun effet hors navigateur
class WebMic {
  static Future<bool> start() async => false;
  static void stop() {}
  static bool get isSupported => false;
}
