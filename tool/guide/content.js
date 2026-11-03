// P1-56: deck/PDF icon comes from the cleaned assets/brand/icons master.
// Shared text for the Attenlume quick guide (deck, PDF and in-app guide).
// UK English. Screenshots live in assets/guide (540 x 1200 JPEG).

module.exports = {
  title: 'Attenlume quick guide',
  subtitle: 'Record sessions, photograph slides, mark key moments, then take home one tidy package.',
  intro:
    'Attenlume keeps the details of a conference so you can give the speaker your attention. ' +
    'Everything stays on your device unless you choose to share it.',
  overview: [
    { n: '1', title: 'Set up', text: 'Create your conference in seconds.' },
    { n: '2', title: 'Capture', text: 'Record, bookmark, note and photograph.' },
    { n: '3', title: 'Review', text: 'Play back, find key moments, trim.' },
    { n: '4', title: 'Export', text: 'Save one package and share it.' },
  ],
  sections: [
    {
      n: '1',
      title: 'Set up',
      blurb: 'One name is all you need to start.',
      steps: [
        {
          title: 'Create your conference',
          images: ['01-create-conference'],
          points: [
            'Use the Settings gear at the top of the opening page to reach settings before creating a conference. Type a name, for example Samlytics Conference 2026.',
            'Tap Create conference. You can add dates and goals later.',
            'Prefer to fill everything in now? Tap Set up with wizard.',
            'Have the programme as a CSV or calendar (ICS) file? Tap Import agenda on the conference page, then pick sessions from it when you start an activity.',
            'Later, tap Open previous to see My conferences. Search by name or place, and use the bar at the bottom (at the side on tablets and Windows) for Record, Library and Settings.',
            'While recording, the status banner and Stop action remain available in Settings as well as the other navigation pages.',
          ],
        },
        {
          title: 'Start an activity',
          images: ['02-conference-home', '03-start-activity'],
          points: [
            'An activity is anything you capture: a keynote, panel, workshop, conversation or your own reflection.',
            'Tap Start activity, add a title if you like, then choose its type.',
            'Quick start buttons create a Session, Conversation, Exhibit or Reflection in one tap.',          ],
        },
      ],
    },
    {
      n: '2',
      title: 'Capture',
      blurb: 'Stay present. Attenlume holds on to the details.',
      steps: [
        {
          title: 'Record',
          images: ['04-ready-to-record', '05-recording'],
          points: [
            'Tap Record. The first time, allow microphone access.',
            'LIVE, the timer and the level meter show it is recording. The line under the timer shows how many hours your storage allows.',
            'Pause or Stop at any time. Recording carries on with the screen locked, and Android shows Stop in the notification.',            'On Windows, minimise to keep recording. Use the tray to reopen, or stop, save and quit. Closing asks first. Shutdown cancels while saving; retry after Attenlume closes.',
          ],
        },
        {
          title: 'Bookmarks and notes',
          images: ['06-bookmark', '07-quick-note'],
          points: [
            'Tap a one-tap bookmark such as Important moment, Question or Follow-up. It is saved at that point in the recording.',
            'Tap Note to write a quick thought.',
            'Tick Mark as private reflection to keep it out of exports.',
            'On Android, long-press the app icon to start, bookmark or stop without opening the app first, or add the Record tile to Quick Settings.',
          ],
        },
        {
          title: 'Photograph slides',
          images: ['08-camera'],
          points: [
            'Tap Photo to open the camera. The recording carries on.',
            'Use the Zoom slider when your camera supports it. The range follows the selected camera; unsupported cameras still take photos. Tap the shutter for each slide or poster. Each photo is linked to its recording time.',
            'Tap the switch button to use the front camera. Tap X to return to the recorder.',
          ],
        },
      ],
    },
    {
      n: '3',
      title: 'Review',
      blurb: 'Find what mattered in minutes, not hours.',
      steps: [
        {
          title: 'Your activities',
          images: ['09-activities', '10-activity-details'],
          points: [
            'Every activity appears on the conference page with its length, photos and bookmarks.',
            'On a wide tablet or Windows window, select a conference to see its overview beside the list: activities, photos, bookmarks and storage used. Search activities by title, speaker or room. Open conference gives you the full start and edit controls.',
            'Tap one to see its notes, bookmarks and photos.',
            'Import photos adds pictures from your gallery. On Android, choose them in the photo picker: Attenlume reads when each was taken, places it on the timeline and marks any taken outside the session. On iPhone and Windows, it lists the photos taken during the session.',
          ],
        },
        {
          title: 'Play, trim and split',
          images: ['11-play-and-review'],
          points: [
            'Tap Play and review. Highlights lists your bookmarks and photos as Key moments: tap one to play from there. Photos and Notes have their own tabs.',
            'On the Timeline tab, use Trim start, Trim end or Start cut to hide parts you do not need. Undo is always there.',
            'Your original recording is never changed unless you choose to apply trims permanently.',
          ],
        },
      ],
    },
    {
      n: '4',
      title: 'Export and share',
      blurb: 'One package for your notes, your team or your AI tool.',
      steps: [
        {
          title: 'What to export',
          images: ['12-export-options', '13-check-before-export'],
          points: [
            'Tap the export button at the top of a conference.',
            'Choose the whole conference, one day or chosen activities, and what to include. On a phone, ZIP is one file you can share.',
            'Private items stay out unless you switch them on. Attenlume asks you to check before every export.',
          ],
        },
        {
          title: 'Save, share and ask AI',
          images: ['14-export-saved', '15-share'],
          points: [
            'When the export is saved, tap Share to send the ZIP to Google Drive, Gmail, Files or an AI app.',
            'Tap Copy AI prompt, then paste it into ChatGPT, Claude or Gemini with the exported files. It already holds your role, goals and the outputs you want.',
            'Inside the export, README_START_HERE explains every file, and timeline.csv lists each bookmark and photo with the exact place in the recording.',
          ],
        },
      ],
    },
    {
      n: '5',
      title: 'Settings and storage',
      blurb: 'Make Attenlume work your way, and keep your device tidy.',
      steps: [
        {
          title: 'Settings',
          images: ['17-menu', '18-settings'],
          points: [
            'Tap Settings in the navigation bar.',
            'Choose the default recording quality, when Attenlume checks in during long recordings, photo quality and the theme.',
            'On Android, turn on Headset button adds a bookmark. While recording, a press of the play or call button on wired or Bluetooth headphones marks the moment without pausing.',
            'Privacy and app lock, the quick guide and About are here too.',
          ],
        },
        {
          title: 'Optional transcription pilot',
          images: ['21-transcription'],
          points: [
            'Open Settings > Optional transcription. It is off by default. Read the conditions before enabling it, then choose Download model (about 31 MB).',
            'For English audio up to 10 minutes per clip, choose audio here or open a saved activity and tap Optional transcription. Activities with audio cuts are not supported yet: import their exported trimmed audio instead. Setup alone never starts transcription.',
            'Review the generated text, correct errors, copy it or share transcript.txt for Notepad, or timestamped transcript.md. Private activity text needs a separate opt-in to copy or share.',
            'Exports with notes include the transcript, with times that match the exported audio. Text from parts you cut is left out of trimmed copies.',
            'Switching off stops processing and keeps audio and saved text. Keep the model for offline use, or explicitly remove it. Live captions will follow this after-recording pilot. If setup fails, read the reason and use Retry setup. A 32-bit Android system is not supported by this pilot.',
          ],
        },
        {
          title: 'Storage manager',
          images: ['19-storage'],
          points: [
            'Open Library, then Files on this device. See how much space each conference uses, and whether it is exported, partly exported or verified.',
            'Clear temporary files at any time. Your recordings and photos are never touched.',
            'Delete local copies is only possible after a complete, verified export of a folder, with a preview and a second confirmation.',
          ],
        },
        {
          title: 'Optional support',
          images: ['23-support-settings'],
          link: { label: 'Support Attenlume on PayPal (optional)', url: 'https://www.paypal.com/donate/?hosted_button_id=EMQCVQHTPDR2U' },
          points: [
            'On eligible direct Android and Windows builds, open Settings > Support Attenlume whenever you choose, even after dismissing export reminders. Your files remain available whether you give or not.',
            'Choose £5, £10, £20 or Other, then Gift now to open PayPal. Choose or change your final amount there.',
            'Maybe later allows one reminder after a later export. Don’t ask again stops these prompts on this device.',
          ],
        },
        {
          title: 'Moving to a new device',
          images: ['20-import'],
          points: [
            'Export the conference, then copy the ZIP to the new device.',
            'On the new device, open Library, then Import an export.',
            'Every file is checked first, and nothing already in the app is overwritten. Transcripts in the export are restored with their recordings.',
          ],
        },
      ],
    },
  ],
  privacy: {
    title: 'Your privacy',
    image: '16-privacy',
    points: [
      'Your conferences, recordings, photos and notes stay on this device unless you export or share them.',
      'No account, no analytics, no adverts and no trackers.',
      'Recording is always shown on screen. There is no hidden recording mode.',
      'Turn on App lock under Settings, Privacy and app lock, to ask for your fingerprint, face or PIN.',
    ],
  },
  tips: [
    { title: 'Ask before you record', text: 'Some events and speakers do not allow recording. Record only when permitted.' },
    { title: 'Long sessions', text: 'Attenlume checks in after two hours, after ten minutes of silence and when the battery is low. Change these in Settings.' },
    { title: 'Updating', text: 'Installing a newer version keeps all your recordings.' },
    { title: 'Before you uninstall', text: 'Uninstalling deletes everything in the app. Export and share your conferences first.' },
  ],
  closing: 'Be present. Bring ideas to light.',
  platforms: 'For Android phones and tablets, and Windows.',
  download: 'github.com/SamsonOluwaseun/attenlume',
};
