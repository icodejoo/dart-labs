import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

void main() {
  group('mpv_event_backend_ffi', () {
    test('allEventIds includes all expected constants', () {
      final ids = allEventIds();
      expect(ids, containsAll([
        generated.mpv_event_id.MPV_EVENT_NONE,
        generated.mpv_event_id.MPV_EVENT_SHUTDOWN,
        generated.mpv_event_id.MPV_EVENT_LOG_MESSAGE,
        generated.mpv_event_id.MPV_EVENT_GET_PROPERTY_REPLY,
        generated.mpv_event_id.MPV_EVENT_SET_PROPERTY_REPLY,
        generated.mpv_event_id.MPV_EVENT_COMMAND_REPLY,
        generated.mpv_event_id.MPV_EVENT_START_FILE,
        generated.mpv_event_id.MPV_EVENT_END_FILE,
        generated.mpv_event_id.MPV_EVENT_FILE_LOADED,
        generated.mpv_event_id.MPV_EVENT_TRACKS_CHANGED,
        generated.mpv_event_id.MPV_EVENT_TRACK_SWITCHED,
        generated.mpv_event_id.MPV_EVENT_IDLE,
        generated.mpv_event_id.MPV_EVENT_PAUSE,
        generated.mpv_event_id.MPV_EVENT_UNPAUSE,
        generated.mpv_event_id.MPV_EVENT_TICK,
        generated.mpv_event_id.MPV_EVENT_SCRIPT_INPUT_DISPATCH,
        generated.mpv_event_id.MPV_EVENT_CLIENT_MESSAGE,
        generated.mpv_event_id.MPV_EVENT_VIDEO_RECONFIG,
        generated.mpv_event_id.MPV_EVENT_AUDIO_RECONFIG,
        generated.mpv_event_id.MPV_EVENT_METADATA_UPDATE,
        generated.mpv_event_id.MPV_EVENT_SEEK,
        generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART,
        generated.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE,
        generated.mpv_event_id.MPV_EVENT_CHAPTER_CHANGE,
        generated.mpv_event_id.MPV_EVENT_QUEUE_OVERFLOW,
        generated.mpv_event_id.MPV_EVENT_HOOK,
      ]));
      expect(ids.length, 26); // Should match the total number of defined events in the library
    });

    test('planEventRequests rules', () {
      final keep = {generated.mpv_event_id.MPV_EVENT_END_FILE, generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART};
      final plan = planEventRequests(keep);
      
      expect(plan.enable, keep);
      
      // SHUTDOWN and NONE never appear
      expect(plan.enable.contains(generated.mpv_event_id.MPV_EVENT_NONE), isFalse);
      expect(plan.disable.contains(generated.mpv_event_id.MPV_EVENT_NONE), isFalse);
      
      expect(plan.enable.contains(generated.mpv_event_id.MPV_EVENT_SHUTDOWN), isFalse);
      expect(plan.disable.contains(generated.mpv_event_id.MPV_EVENT_SHUTDOWN), isFalse);
      
      // All others outside keep are in disable
      for (final id in allEventIds()) {
        if (id == generated.mpv_event_id.MPV_EVENT_NONE || id == generated.mpv_event_id.MPV_EVENT_SHUTDOWN) continue;
        if (keep.contains(id)) {
          expect(plan.enable.contains(id), isTrue);
          expect(plan.disable.contains(id), isFalse);
        } else {
          expect(plan.enable.contains(id), isFalse);
          expect(plan.disable.contains(id), isTrue);
        }
      }
    });

    test('copyEvent rules', () {
      // NONE -> null
      expect(copyEvent(generated.mpv_event_id.MPV_EVENT_NONE, () => 1), isNull);
      
      // non END_FILE -> reasonReader not called
      var called = false;
      final nonEndFile = copyEvent(generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART, () {
        called = true;
        return 1;
      });
      expect(nonEndFile?.id, generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART);
      expect(nonEndFile?.endFileReason, isNull);
      expect(called, isFalse);
      
      // END_FILE -> reasonReader called
      final endFile = copyEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, () {
        called = true;
        return 2;
      });
      expect(endFile?.id, generated.mpv_event_id.MPV_EVENT_END_FILE);
      expect(endFile?.endFileReason, 2);
      expect(called, isTrue);

      // END_FILE reason reader returns null -> endFileReason is null
      final endFileNullReason = copyEvent(generated.mpv_event_id.MPV_EVENT_END_FILE, () => null);
      expect(endFileNullReason?.endFileReason, isNull);
    });
  });
}
