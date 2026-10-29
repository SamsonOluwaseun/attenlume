// GENERATED from the quick guide source (content.js). Do not edit by hand.
// The same text builds docs/user-guide/Attenlume-Quick-Guide.pptx and .pdf.

import 'guide_model.dart';

const quickGuide = QuickGuide(
  title: 'Attenlume quick guide',
  intro: 'Attenlume keeps the details of a conference so you can give the speaker your attention. Everything stays on your device unless you choose to share it.',
  overview: [
    GuideOverviewItem(
      number: '1',
      title: 'Set up',
      text: 'Create your conference in seconds.',
    ),
    GuideOverviewItem(
      number: '2',
      title: 'Capture',
      text: 'Record, bookmark, note and photograph.',
    ),
    GuideOverviewItem(
      number: '3',
      title: 'Review',
      text: 'Play back, find key moments, trim.',
    ),
    GuideOverviewItem(
      number: '4',
      title: 'Export',
      text: 'Save one package and share it.',
    ),
  ],
  sections: [
    GuideSection(
      number: '1',
      title: 'Set up',
      blurb: 'One name is all you need to start.',
      steps: [
        GuideStep(
          title: 'Create your conference',
          images: ['01-create-conference'],
          points: [
            'Type the conference name, for example Samlytics Conference 2026.',
            'Tap Create conference. You can add dates and goals later.',
            'Prefer to fill everything in now? Tap Set up with wizard.',
          ],
        ),
        GuideStep(
          title: 'Start an activity',
          images: ['02-conference-home', '03-start-activity'],
          points: [
            'An activity is anything you capture: a keynote, panel, workshop, conversation or your own reflection.',
            'Tap Start activity, add a title if you like, then choose its type.',
            'Quick start buttons create a Session, Conversation, Exhibit or Reflection in one tap.',
          ],
        ),
      ],
    ),
    GuideSection(
      number: '2',
      title: 'Capture',
      blurb: 'Stay present. Attenlume holds on to the details.',
      steps: [
        GuideStep(
          title: 'Record',
          images: ['04-ready-to-record', '05-recording'],
          points: [
            'Tap Record. The first time, allow microphone access.',
            'LIVE, the timer and the level meter show it is recording. The line under the timer shows how many hours your storage allows.',
            'Pause or Stop at any time. Recording carries on with the screen locked, and Android shows Stop in the notification.',
          ],
        ),
        GuideStep(
          title: 'Bookmarks and notes',
          images: ['06-bookmark', '07-quick-note'],
          points: [
            'Tap a one-tap bookmark such as Important moment, Question or Follow-up. It is saved at that point in the recording.',
            'Tap Note to write a quick thought.',
            'Tick Mark as private reflection to keep it out of exports.',
          ],
        ),
        GuideStep(
          title: 'Photograph slides',
          images: ['08-camera'],
          points: [
            'Tap Photo to open the camera. The recording carries on.',
            'Tap the shutter for each slide or poster. Each photo is linked to the moment it was taken.',
            'Tap the switch button to use the front camera. Tap X to return to the recorder.',
          ],
        ),
      ],
    ),
    GuideSection(
      number: '3',
      title: 'Review',
      blurb: 'Find what mattered in minutes, not hours.',
      steps: [
        GuideStep(
          title: 'Your activities',
          images: ['09-activities', '10-activity-details'],
          points: [
            'Every activity appears on the conference page with its length, photos and bookmarks.',
            'Tap one to see its notes, bookmarks and photos.',
            'Import photos adds pictures from your gallery taken during the session.',
          ],
        ),
        GuideStep(
          title: 'Play, trim and split',
          images: ['11-play-and-review'],
          points: [
            'Tap Play and review. Bookmarks and photos appear on the timeline and under Key moments.',
            'Use Trim start, Trim end or Start cut to hide parts you do not need. Undo is always there.',
            'Your original recording is never changed unless you choose to apply trims permanently.',
          ],
        ),
      ],
    ),
    GuideSection(
      number: '4',
      title: 'Export and share',
      blurb: 'One package for your notes, your team or your AI tool.',
      steps: [
        GuideStep(
          title: 'What to export',
          images: ['12-export-options', '13-check-before-export'],
          points: [
            'Tap the export button at the top of a conference.',
            'Choose the whole conference, one day or chosen activities, and what to include. On a phone, ZIP is one file you can share.',
            'Private items stay out unless you switch them on. Attenlume asks you to check before every export.',
          ],
        ),
        GuideStep(
          title: 'Save and share',
          images: ['14-export-saved', '15-share'],
          points: [
            'When the export is saved, tap Share.',
            'Send the ZIP to Google Drive, Gmail, Files or an AI app.',
            'A copy stays in Attenlume. Checksums inside the ZIP let you confirm nothing changed.',
          ],
        ),
      ],
    ),
  ],
  privacyTitle: 'Your privacy',
  privacyImage: '16-privacy',
  privacyPoints: [
    'Your conferences, recordings, photos and notes stay on this device unless you export or share them.',
    'No account, no analytics, no adverts and no trackers.',
    'Recording is always shown on screen. There is no hidden recording mode.',
    'Turn on App lock under My conferences, menu, Settings, Privacy and app lock, to ask for your fingerprint, face or PIN.',
  ],
  tips: [
    GuideTip(
      title: 'Ask before you record',
      text: 'Some events and speakers do not allow recording. Record only when permitted.',
    ),
    GuideTip(
      title: 'Long sessions',
      text: 'Attenlume checks in after two hours, after ten minutes of silence and when the battery is low. Change these in Settings.',
    ),
    GuideTip(
      title: 'Updating',
      text: 'Installing a newer version keeps all your recordings.',
    ),
    GuideTip(
      title: 'Moving to a new device',
      text: 'Export a conference, then on the new device open My conferences, menu, Import an export. Every file is checked first, and nothing already in the app is overwritten.',
    ),
    GuideTip(
      title: 'Before you uninstall',
      text: 'Uninstalling deletes everything in the app. Export and share your conferences first.',
    ),
  ],
  closing: 'Be present. Bring ideas to light.',
);
