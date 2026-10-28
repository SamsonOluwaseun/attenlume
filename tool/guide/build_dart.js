// Writes lib/features/guide/guide_content.dart from content.js, so the app,
// the deck and the PDF share one text.
const fs = require('fs');
const G = require('./content');

const q = (s) => `'${s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;
const list = (xs, f, ind) => `[\n${xs.map((x) => `${ind}  ${f(x)},`).join('\n')}\n${ind}]`;

const step = (s, ind) =>
  `GuideStep(\n${ind}  title: ${q(s.title)},\n${ind}  images: ${list(s.images, q, ind + '  ')},\n${ind}  points: ${list(s.points, q, ind + '  ')},\n${ind})`;

const out = `// GENERATED from the quick guide source (content.js). Do not edit by hand.
// The same text builds docs/user-guide/Attenlume-Quick-Guide.pptx and .pdf.

import 'guide_model.dart';

const quickGuide = QuickGuide(
  title: ${q(G.title)},
  intro: ${q(G.intro)},
  overview: ${list(G.overview, (o) => `GuideOverviewItem(number: ${q(o.n)}, title: ${q(o.title)}, text: ${q(o.text)})`, '  ')},
  sections: ${list(G.sections, (s) => `GuideSection(\n      number: ${q(s.n)},\n      title: ${q(s.title)},\n      blurb: ${q(s.blurb)},\n      steps: ${list(s.steps, (st) => step(st, '        '), '      ')},\n    )`, '  ')},
  privacyTitle: ${q(G.privacy.title)},
  privacyImage: ${q(G.privacy.image)},
  privacyPoints: ${list(G.privacy.points, q, '  ')},
  tips: ${list(G.tips, (t) => `GuideTip(title: ${q(t.title)}, text: ${q(t.text)})`, '  ')},
  closing: ${q(G.closing)},
);
`;
fs.writeFileSync(process.argv[2], out, 'utf8');
console.log('wrote ' + process.argv[2]);
