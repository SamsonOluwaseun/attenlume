# ActivityCard

One activity in a conference timeline: type, title, time, recording state and what was captured.

**Consumer provides:** `type` (session, keynote, conversation, exhibit, reflection or custom), `title`, `startTime`, `location` (optional), `state` (for the StatusPill), `duration`, `photoCount`, `bookmarkCount`, `profile` (Economy, Balanced, Enhanced), `onOpen`.

**Anatomy:** `surface-raised` card, `radius-md`, padding `space-4`. Row 1: type label in `caption` plus the StatusPill on the right. Row 2: title in `heading`. Row 3: metadata in `body-small` `ink-muted` ("09:30 · Hall A · 47 min"). Row 4: counts with icons (camera 12, bookmark 4) and the quality profile.

**Rules**

- The whole card is one tap target with a label that reads the title, state and duration.
- An activity that is recording now shows the Recording StatusPill (navy with a lime dot) and moves to the top of the list. Never a lime mark on cream.
- Private activities (conversations, reflections) show a lock icon and "Private" so users see what is excluded from exports by default.
- Long titles wrap to two lines, then truncate.
