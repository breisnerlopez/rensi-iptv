import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/services/sleep_timer_service.dart';

void main() {
  group('SleepTimerService', () {
    late SleepTimerService service;

    setUp(() {
      service = SleepTimerService.instance;
      // Reset shared singleton state in case a previous test left it
      // active; tearDown also calls cancel() but setUp guards the case
      // where a test threw before reaching tearDown.
      service.cancel();
    });

    tearDown(() {
      service.cancel();
    });

    test('starts idle', () {
      expect(service.isActive, isFalse);
      expect(service.remaining.value, isNull);
    });

    test('start(5s) reports active and exposes initial duration', () {
      fakeAsync((_) {
        service.start(const Duration(seconds: 5));
        expect(service.isActive, isTrue);
        expect(service.remaining.value, const Duration(seconds: 5));
      });
    });

    test('remaining notifier ticks down once per second', () {
      fakeAsync((async) {
        service.start(const Duration(seconds: 3));
        expect(service.remaining.value, const Duration(seconds: 3));

        async.elapse(const Duration(seconds: 1));
        expect(service.remaining.value, const Duration(seconds: 2));

        async.elapse(const Duration(seconds: 1));
        expect(service.remaining.value, const Duration(seconds: 1));

        async.elapse(const Duration(seconds: 1));
        // At zero the fire path resets `remaining` to null.
        expect(service.remaining.value, isNull);
        expect(service.isActive, isFalse);
      });
    });

    test('fires exactly once when countdown hits zero', () {
      fakeAsync((async) {
        var fireCount = 0;
        final sub = service.onFire.listen((_) => fireCount++);

        service.start(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        // Flush any pending microtasks from the stream controller.
        async.flushMicrotasks();

        expect(fireCount, 1);
        expect(service.isActive, isFalse);
        expect(service.remaining.value, isNull);

        sub.cancel();
      });
    });

    test('cancel() before fire stops the countdown and emits no event', () {
      fakeAsync((async) {
        var fireCount = 0;
        final sub = service.onFire.listen((_) => fireCount++);

        service.start(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 4));
        expect(service.remaining.value, const Duration(seconds: 6));

        service.cancel();
        expect(service.isActive, isFalse);
        expect(service.remaining.value, isNull);

        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(fireCount, 0);

        sub.cancel();
      });
    });

    test('start() while active replaces the previous timer', () {
      fakeAsync((async) {
        var fireCount = 0;
        final sub = service.onFire.listen((_) => fireCount++);

        service.start(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 3));
        expect(service.remaining.value, const Duration(seconds: 7));

        service.start(const Duration(seconds: 2));
        expect(service.remaining.value, const Duration(seconds: 2));

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(fireCount, 1, reason: 'only the second timer should fire');

        sub.cancel();
      });
    });

    test('Duration.zero fires asynchronously without ticking', () {
      fakeAsync((async) {
        var fireCount = 0;
        final sub = service.onFire.listen((_) => fireCount++);

        service.start(Duration.zero);
        expect(fireCount, 0, reason: 'fire is scheduled, not synchronous');

        async.flushMicrotasks();
        // Zero-delay Timer fires when the next event-loop turn runs.
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(fireCount, 1);
        expect(service.remaining.value, isNull);

        sub.cancel();
      });
    });

    test('negative duration behaves like zero', () {
      fakeAsync((async) {
        var fireCount = 0;
        final sub = service.onFire.listen((_) => fireCount++);

        service.start(const Duration(seconds: -5));
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(fireCount, 1);
        sub.cancel();
      });
    });

    test('cancel() is idempotent', () {
      service.cancel();
      service.cancel();
      service.cancel();
      expect(service.isActive, isFalse);
    });
  });
}
