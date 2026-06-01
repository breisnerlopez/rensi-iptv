import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/channel_number_buffer.dart';

void main() {
  group('ChannelNumberBuffer', () {
    late ChannelNumberBuffer buf;
    late List<int> commits;

    setUp(() {
      buf = ChannelNumberBuffer();
      commits = <int>[];
      buf.onCommit.listen(commits.add);
    });

    tearDown(() {
      buf.dispose();
    });

    test('starts idle and empty', () {
      expect(buf.buffer.value, '');
      expect(buf.isActive, isFalse);
    });

    test('appendDigit accumulates left-to-right', () {
      fakeAsync((_) {
        buf.appendDigit(4);
        buf.appendDigit(2);
        expect(buf.buffer.value, '42');
        expect(buf.isActive, isTrue);
      });
    });

    test('digits outside 0-9 are ignored', () {
      buf.appendDigit(-1);
      buf.appendDigit(10);
      buf.appendDigit(99);
      expect(buf.buffer.value, '');
    });

    test('idleTimeout auto-commits and clears', () {
      fakeAsync((async) {
        buf.appendDigit(7);
        async.elapse(const Duration(milliseconds: 1499));
        expect(commits, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(commits, equals([7]));
        expect(buf.buffer.value, '');
      });
    });

    test('maxDigits triggers immediate commit', () {
      fakeAsync((async) {
        for (final d in [1, 2, 3, 4]) {
          buf.appendDigit(d);
        }
        async.flushMicrotasks();
        expect(commits, equals([1234]));
        expect(buf.buffer.value, '');
        // Further digits do not extend a previously-committed buffer.
        buf.appendDigit(5);
        expect(buf.buffer.value, '5');
      });
    });

    test('further digits after reaching maxDigits are ignored on commit-line',
        () {
      fakeAsync((async) {
        for (final d in [9, 9, 9, 9]) {
          buf.appendDigit(d);
        }
        async.flushMicrotasks();
        // 5th digit was never present in this commit.
        expect(commits, equals([9999]));
      });
    });

    test('typing resets the idle timer (so 1s gap inside is fine)', () {
      fakeAsync((async) {
        buf.appendDigit(1);
        async.elapse(const Duration(milliseconds: 1000));
        buf.appendDigit(2);
        async.elapse(const Duration(milliseconds: 1000));
        expect(commits, isEmpty, reason: 'still inside the 1.5s window');
        async.elapse(const Duration(milliseconds: 500));
        expect(commits, equals([12]));
      });
    });

    test('backspace removes the last digit and cancels timer when empty', () {
      fakeAsync((async) {
        buf.appendDigit(8);
        buf.appendDigit(8);
        buf.backspace();
        expect(buf.buffer.value, '8');

        buf.backspace();
        expect(buf.buffer.value, '');
        expect(buf.isActive, isFalse);

        // No commit should fire even after the would-be timeout window.
        async.elapse(const Duration(milliseconds: 5000));
        expect(commits, isEmpty);
      });
    });

    test('backspace on empty buffer is a no-op', () {
      buf.backspace();
      buf.backspace();
      expect(buf.buffer.value, '');
    });

    test('commit() with empty buffer is a no-op', () {
      buf.commit();
      expect(commits, isEmpty);
    });

    test('clear() empties without emitting onCommit', () {
      fakeAsync((async) {
        buf.appendDigit(5);
        buf.appendDigit(0);
        buf.clear();
        expect(buf.buffer.value, '');
        async.elapse(const Duration(milliseconds: 3000));
        expect(commits, isEmpty);
      });
    });

    test('custom idleTimeout and maxDigits are honored', () {
      final custom = ChannelNumberBuffer(
        idleTimeout: const Duration(milliseconds: 500),
        maxDigits: 2,
      );
      final emitted = <int>[];
      final sub = custom.onCommit.listen(emitted.add);

      fakeAsync((async) {
        custom.appendDigit(3);
        custom.appendDigit(7);
        // maxDigits=2 triggers immediate commit on the second digit.
        async.flushMicrotasks();
        expect(emitted, equals([37]));

        custom.appendDigit(9);
        async.elapse(const Duration(milliseconds: 499));
        expect(emitted, equals([37]), reason: 'still inside the 500ms window');
        async.elapse(const Duration(milliseconds: 1));
        expect(emitted, equals([37, 9]));
      });

      sub.cancel();
      custom.dispose();
    });

    test('dispose stops emissions and is idempotent', () {
      fakeAsync((async) {
        final isolated = ChannelNumberBuffer();
        final received = <int>[];
        isolated.onCommit.listen(received.add);

        isolated.appendDigit(4);
        isolated.appendDigit(2);
        isolated.commit();
        async.flushMicrotasks();
        expect(received, equals([42]));

        isolated.dispose();
        isolated.dispose();

        // After dispose, further commits are silently dropped (the
        // controller is closed and the guard in commit() blocks add()).
        expect(() => isolated.commit(), returnsNormally);
      });
    });
  });
}
