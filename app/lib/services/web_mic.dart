// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// Accès micro via l'API Web Audio — utilisé uniquement sur Flutter web.
/// getUserMedia → AudioContext → connexion directe au casque/hauts-parleurs.
class WebMic {
  static bool get isSupported => true;

  static Future<bool> start() async {
    js.context.callMethod('eval', [r"""
      if (!window._kkMic) {
        navigator.mediaDevices.getUserMedia({ audio: true, video: false })
          .then(function(stream) {
            var ctx = new (window.AudioContext || window.webkitAudioContext)();
            ctx.createMediaStreamSource(stream).connect(ctx.destination);
            window._kkMic = { stream: stream, ctx: ctx };
          })
          .catch(function(e) { console.error('[KaraOrKey] Mic error:', e); });
      }
    """]);
    return true;
  }

  static void stop() {
    js.context.callMethod('eval', [r"""
      if (window._kkMic) {
        window._kkMic.stream.getTracks().forEach(function(t) { t.stop(); });
        window._kkMic.ctx.close();
        delete window._kkMic;
      }
    """]);
  }
}
