import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  static const String hmacSecret = "G7kP2xQ9mL4z";

  static String randNonce([int bytes = 12]) {
    final r = Random.secure();
    final b = List<int>.generate(bytes, (_) => r.nextInt(256));
    // base64url without padding
    return base64UrlEncode(b).replaceAll('=', '');
  }

  static String hmacHex(String canonical) {
    final key = utf8.encode(hmacSecret);
    final msg = utf8.encode(canonical);
    final digest = Hmac(sha256, key).convert(msg);
    return digest.toString(); // hex
  }

  static Map<String, String> buildHmacParams({
    required String roomId,
    required String role, // "host" or "viewer"
    required String sessionId,
  }) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = randNonce();

    // MUST match Go canonical exactly:
    final canonical = "roomId=$roomId&role=$role&sessionId=$sessionId&ts=$ts&nonce=$nonce";

    final sig = hmacHex(canonical);
    return {"sessionId": sessionId, "ts": ts, "nonce": nonce, "sig": sig};
  }

  static String newSessionId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
