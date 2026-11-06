"""Sample a held diagnostic phase; token equality rejects crossed/expired scenes."""
from shot_guard import guarded_frame_pair
import subprocess


def is_capture_marker(line):
    return (' SHOT ' in line or ' MARK ' in line) and 'SHOT_ACK ' not in line


def capture_phase(adb, package, paths, token, fetch):
    before = fetch('/')
    if before.get('token') != token:
        return dict(captured=False, phaseConfirmed=False, reason='expired phase token', before=before)
    attempts = []
    for attempt in range(2):
        try:
            capture = guarded_frame_pair(adb, package, paths)
            attempts.append(dict(captured=capture.get('captured', False)))
            break
        except subprocess.TimeoutExpired as error:
            capture = dict(captured=False, error=repr(error))
            attempts.append(capture)
            # Retry transport only while the exact same phase is still held.
            # Never retake a visually failing or privacy-rejected image.
            if attempt or fetch('/').get('token') != token:
                break
        except Exception as error:
            capture = dict(captured=False, error=repr(error))
            attempts.append(capture)
            break
    after = fetch('/')
    same = after.get('token') == token
    ack = fetch('/ack?token='+token) if same else {}
    confirmed = same and ack.get('token') == token and ack.get('acknowledged') is True
    return dict(captured=capture.get('captured', False) and confirmed,
                phaseConfirmed=confirmed, token=token, before=before, after=after,
                ack=ack, capture=capture, attempts=attempts, frames=capture.get('frames', []))
