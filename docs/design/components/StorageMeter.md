# StorageMeter

Shows free space and recording time left at the current quality, so the user is never surprised by a full phone (FR-UI-07, FR-STO-01).

**Consumer provides:** `freeBytes`, `minutesLeft` (measured, not nominal), `profile`, `level` (`ok`, `low`, `critical`), `onManage`.

**Rules**

- Lead with time, not bytes: "About 9 h 40 min left at Balanced". Bytes go second in `body-small`.
- Bar track `line`, fill `brand` when ok. Low (under 1 GB or 60 min): a `warning-fill` banner with an icon and "Running low. Export or free space soon." Critical (near 300 MB): `danger` fill and "Storage nearly full. Recording will stop safely."
- On the recording screen it shrinks to one muted line under the timer and only grows into a banner at low or critical.
- Never use colour alone: every level has its own sentence.
