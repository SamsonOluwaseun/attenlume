import 'package:attenlume/domain/ai/summary_quality.dart';

/// The scored Samlytics Conference 2026 test set for session summaries
/// (ADR-076 item 4). Every model, local or own-key, must pass all cases
/// before it is listed or replaced. Facts are lower-case phrases; forbidden
/// claims are plausible things the sessions never said.
const summaryQualitySet = <SummaryQualityCase>[
  SummaryQualityCase(
    id: 'q_data_quality',
    title: 'Data quality for small teams',
    speech: [
      (
        0,
        'Welcome to Samlytics Conference 2026. This talk is about data quality when your team is small.',
      ),
      (
        14,
        'Most small teams do not need a data quality platform. They need three habits.',
      ),
      (
        29,
        'The first habit is to write down what each column means before anyone builds a report on it.',
      ),
      (
        47,
        'At Samlytics Data Services we call that a data dictionary, and ours started as a shared spreadsheet.',
      ),
      (
        66,
        'The second habit is to check row counts every morning. If yesterday had ten thousand orders and today has twelve, something broke.',
      ),
      (
        88,
        'A simple row count check caught four broken imports for us in the last quarter.',
      ),
      (
        104,
        'The third habit is to give every dataset an owner, one named person who answers questions about it.',
      ),
      (122, 'Without an owner, problems bounce between teams for weeks.'),
      (
        139,
        'Someone asked about tools. Start with what you have. A scheduled query and an email alert is enough.',
      ),
      (
        160,
        'Only buy a platform when you have more than about fifty datasets to watch.',
      ),
      (
        178,
        'My action for you: this week, pick your five most used tables and write one sentence about each column.',
      ),
      (
        199,
        'I will share our dictionary template on the conference page after the session.',
      ),
      (215, 'Thank you, and enjoy the rest of Samlytics Conference 2026.'),
    ],
    bookmarks: [(offsetMs: 88000, label: 'Row counts', note: null)],
    notesMd: '- Ask about the template',
    expectedFacts: [
      [
        'data dictionary',
        'what each column means',
        'describe each column',
        'column',
      ],
      ['row count'],
      ['owner'],
      ['fifty datasets', '50 datasets', 'buy a platform', 'platform'],
      ['template'],
      ['five most used tables', 'five tables', '5 tables', 'five most-used'],
    ],
    forbidden: ['machine learning', 'ninety percent', 'snowflake', 'gdpr fine'],
  ),
  SummaryQualityCase(
    id: 'q_offline_first',
    title: 'Building offline-first mobile apps',
    speech: [
      (
        0,
        'Good afternoon. I want to make the case for apps that work without a signal.',
      ),
      (
        12,
        'Conference halls are a good example. Hundreds of phones, one weak network.',
      ),
      (
        27,
        'Offline first means the phone is the source of truth and the network is a bonus.',
      ),
      (
        43,
        'Store everything locally in a database on the device and write to it first.',
      ),
      (
        61,
        'Sync later, in the background, and design for conflicts from day one.',
      ),
      (
        79,
        'The simplest conflict rule is last write wins, but it loses data when two people edit the same thing.',
      ),
      (
        98,
        'For notes we keep both versions and ask the user, which sounds annoying but happens rarely.',
      ),
      (
        118,
        'Test it properly. Put the phone in airplane mode for a whole day and use the app normally.',
      ),
      (137, 'Our team found eleven bugs in the first airplane mode day.'),
      (
        152,
        'Battery matters too. Do not retry the network every second; back off.',
      ),
      (
        169,
        'Question from the room about large files: upload them only on Wi-Fi unless the user says otherwise.',
      ),
      (
        190,
        'Follow up: I will publish our airplane mode test checklist next week.',
      ),
    ],
    bookmarks: [(offsetMs: 137000, label: 'Eleven bugs', note: 'try this')],
    expectedFacts: [
      ['source of truth', 'locally', 'on the device'],
      ['conflict'],
      ['last write wins'],
      ['airplane mode'],
      ['eleven bugs', '11 bugs'],
      ['wi-fi', 'wifi'],
      ['checklist'],
    ],
    forbidden: [
      '5g',
      'blockchain',
      'cloud database is required',
      'thirty bugs',
    ],
  ),
  SummaryQualityCase(
    id: 'q_ai_pilot',
    title: 'Running a small AI pilot',
    speech: [
      (
        0,
        'This session from Samlytics Data Services is about running an AI pilot without wasting a year.',
      ),
      (
        16,
        'Pick one task that people already do by hand, for example sorting support emails.',
      ),
      (
        33,
        'Measure how long it takes today before you change anything. We timed it at six minutes per email.',
      ),
      (
        52,
        'Run the pilot for six weeks, no longer, with a small group of volunteers.',
      ),
      (
        70,
        'Keep a person checking every answer in the pilot. The AI suggests, a person decides.',
      ),
      (88, 'In our pilot the time per email fell from six minutes to two.'),
      (
        105,
        'But the AI was wrong about one email in twelve, which is why the checking matters.',
      ),
      (
        124,
        'Decide in advance what result means stop, and what result means continue.',
      ),
      (
        141,
        'Our rule was: continue only if time falls by half and errors stay below one in ten.',
      ),
      (
        160,
        'Next step for us is a second pilot on meeting notes, starting in January.',
      ),
      (
        178,
        'If you want our pilot plan, ask at the Samlytics Data Services stand.',
      ),
    ],
    notesMd: 'Compare with our support team numbers',
    expectedFacts: [
      ['one task', 'single task', 'sorting support emails', 'support email'],
      ['six minutes', '6 minutes'],
      ['six weeks', '6 weeks'],
      ['person', 'human'],
      ['two minutes', '2 minutes', 'from six minutes to two', 'six to two'],
      ['one in twelve', '1 in 12'],
      ['meeting notes'],
    ],
    forbidden: [
      'chatgpt',
      'one year pilot',
      'replaced the support team',
      'fully automated',
    ],
  ),
];
