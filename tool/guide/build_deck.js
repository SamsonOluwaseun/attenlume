// Builds the Attenlume quick guide deck (Samlytics brand, PptxGenJS).
const path = require('path');
const pptxgen = require('pptxgenjs');
const G = require('./content');

const REPO = require('path').resolve(__dirname, '..', '..').replace(/\\/g, '/');
const IMG = `${REPO}/assets/guide`;
const ICON = `${REPO}/assets/brand/icons/attenlume-app-icon-filled.png`;
const OUT = process.argv[2] || 'Attenlume-Quick-Guide.pptx';

const C = { blue: '4392F1', navy: '00212B', cream: 'FEFFF8', lime: 'DCFF38', limeDk: 'C2E812', tint: 'EAF2FD' };
const FONT = 'Montserrat';

const pres = new pptxgen();
pres.layout = 'LAYOUT_16x9'; // 10 x 5.625 in
pres.title = G.title;
pres.author = 'Samlytics Data Services';
pres.company = 'Samlytics Data Services';
pres.theme = { headFontFace: FONT, bodyFontFace: FONT };

pres.defineSlideMaster({
  title: 'CONTENT',
  background: { color: C.cream },
  objects: [
    { text: { text: 'Attenlume quick guide', options: { x: 0.5, y: 5.2, w: 4, h: 0.3, fontFace: FONT, fontSize: 9, color: '5B6B70', margin: 0 } } },
  ],
  slideNumber: { x: 9.1, y: 5.2, w: 0.4, h: 0.3, fontFace: FONT, fontSize: 9, color: '5B6B70', align: 'right' },
});

function pills(slide, onBlue) {
  const main = onBlue ? C.cream : C.blue;
  slide.addShape(pres.ShapeType.roundRect, { x: 8.6, y: -0.35, w: 2.8, h: 0.7, rectRadius: 0.35, fill: { color: main }, line: { color: main }, rotate: 30 });
  slide.addShape(pres.ShapeType.roundRect, { x: 9.0, y: 0.55, w: 1.6, h: 0.45, rectRadius: 0.22, fill: { color: C.lime }, line: { color: C.lime }, rotate: 30 });
  slide.addShape(pres.ShapeType.roundRect, { x: -0.7, y: 5.05, w: 2.2, h: 0.55, rectRadius: 0.27, fill: { color: C.lime }, line: { color: C.lime }, rotate: 30 });
}

// A screenshot in a navy phone frame. Images are 540 x 1200 (0.45 ratio).
function phone(slide, name, x, y, h) {
  const w = h * 0.45;
  const pad = 0.07;
  slide.addShape(pres.ShapeType.roundRect, {
    x: x - pad, y: y - pad, w: w + 2 * pad, h: h + 2 * pad, rectRadius: 0.18,
    fill: { color: C.navy }, line: { color: C.navy },
    shadow: { type: 'outer', color: '000000', opacity: 0.18, blur: 8, offset: 3, angle: 90 },
  });
  slide.addImage({ path: `${IMG}/${name}.jpg`, x, y, w, h, altText: `Attenlume screen: ${name.replace(/^\d+-/, '').replace(/-/g, ' ')}` });
  return w + 2 * pad;
}

function stepSlide(section, step) {
  const s = pres.addSlide({ masterName: 'CONTENT', sectionTitle: section.title });
  // Section chip
  s.addShape(pres.ShapeType.roundRect, { x: 0.5, y: 0.45, w: 1.9, h: 0.34, rectRadius: 0.17, fill: { color: C.lime }, line: { color: C.lime } });
  s.addText(`${section.n}  ${section.title}`, { x: 0.5, y: 0.45, w: 1.9, h: 0.34, fontFace: FONT, fontSize: 11, bold: true, color: C.navy, align: 'center', valign: 'middle', margin: 0, isTextBox: true });
  // Phones on the right, 4.25 in tall; the text column ends 0.35 in before them.
  const h = 4.25;
  const w = h * 0.45 + 0.14;
  const gap = 0.3;
  const total = step.images.length * w + (step.images.length - 1) * gap;
  const textW = 9.5 - total - 0.35 - 0.5;

  s.addText(step.title, { x: 0.5, y: 0.95, w: textW, h: 0.85, fontFace: FONT, fontSize: textW < 4.3 ? 24 : 28, bold: true, color: C.blue, margin: 0, valign: 'top', isTextBox: true });

  const items = step.points.map((p, i) => ({
    text: p,
    options: { bullet: { indent: 15 }, breakLine: i < step.points.length - 1, paraSpaceAfter: 10 },
  }));
  s.addText(items, { x: 0.5, y: 1.95, w: textW, h: 3.0, fontFace: FONT, fontSize: 14, color: C.navy, valign: 'top', margin: 0, isTextBox: true });

  let x = 9.5 - total + 0.07;
  for (const img of step.images) {
    phone(s, img, x, 0.55, h);
    x += w + gap;
  }
  return s;
}

// 1. Title
{
  pres.addSection({ title: 'Welcome' });
  const s = pres.addSlide({ sectionTitle: 'Welcome' });
  s.background = { color: C.blue };
  pills(s, true);
  s.addText('Samlytics Data Services', { x: 0.5, y: 0.35, w: 5, h: 0.3, fontFace: FONT, fontSize: 11, color: C.cream, margin: 0, isTextBox: true });
  s.addImage({ path: ICON, x: 4.35, y: 0.95, w: 1.3, h: 1.3, altText: 'Attenlume app icon' });
  s.addText(G.title, { x: 0.75, y: 2.45, w: 8.5, h: 0.9, fontFace: FONT, fontSize: 42, bold: true, color: C.cream, align: 'center', margin: 0, isTextBox: true });
  s.addText(G.subtitle, { x: 1.25, y: 3.4, w: 7.5, h: 0.75, fontFace: FONT, fontSize: 17, color: C.lime, align: 'center', margin: 0, isTextBox: true });
  s.addText(G.platforms, { x: 1.25, y: 4.45, w: 7.5, h: 0.35, fontFace: FONT, fontSize: 11, color: C.cream, align: 'center', margin: 0, isTextBox: true });
}

// 2. Overview
{
  const s = pres.addSlide({ masterName: 'CONTENT', sectionTitle: 'Welcome' });
  s.addText('Four steps, one tidy package', { x: 0.5, y: 0.45, w: 9, h: 0.7, fontFace: FONT, fontSize: 32, bold: true, color: C.blue, margin: 0, isTextBox: true });
  s.addText(G.intro, { x: 0.5, y: 1.2, w: 8.6, h: 0.65, fontFace: FONT, fontSize: 14, color: C.navy, margin: 0, isTextBox: true });
  const cw = 2.0, ch = 2.3, gap = 0.2, y = 2.25;
  G.overview.forEach((o, i) => {
    const x = 0.5 + i * (cw + gap);
    s.addShape(pres.ShapeType.roundRect, { x, y, w: cw, h: ch, rectRadius: 0.15, fill: { color: C.blue }, line: { color: C.blue } });
    s.addShape(pres.ShapeType.ellipse, { x: x + 0.2, y: y + 0.22, w: 0.55, h: 0.55, fill: { color: C.lime }, line: { color: C.lime } });
    s.addText(o.n, { x: x + 0.2, y: y + 0.22, w: 0.55, h: 0.55, fontFace: FONT, fontSize: 18, bold: true, color: C.navy, align: 'center', valign: 'middle', margin: 0, isTextBox: true });
    s.addText(o.title, { x: x + 0.2, y: y + 0.95, w: cw - 0.4, h: 0.45, fontFace: FONT, fontSize: 18, bold: true, color: C.cream, margin: 0, isTextBox: true });
    s.addText(o.text, { x: x + 0.2, y: y + 1.4, w: cw - 0.4, h: 0.75, fontFace: FONT, fontSize: 12, color: C.cream, margin: 0, valign: 'top', isTextBox: true });
  });
}

// Sections
for (const section of G.sections) {
  pres.addSection({ title: section.title });
  const d = pres.addSlide({ sectionTitle: section.title });
  d.background = { color: C.navy };
  d.addShape(pres.ShapeType.roundRect, { x: -0.6, y: 4.9, w: 2.4, h: 0.55, rectRadius: 0.27, fill: { color: C.lime }, line: { color: C.lime }, rotate: 30 });
  d.addShape(pres.ShapeType.roundRect, { x: 8.7, y: -0.3, w: 2.4, h: 0.6, rectRadius: 0.3, fill: { color: C.blue }, line: { color: C.blue }, rotate: 30 });
  d.addText(section.n, { x: 0.75, y: 1.35, w: 1.5, h: 1.1, fontFace: FONT, fontSize: 66, bold: true, color: C.lime, margin: 0, isTextBox: true });
  d.addText(section.title, { x: 0.75, y: 2.45, w: 5.2, h: 0.8, fontFace: FONT, fontSize: 40, bold: true, color: C.cream, margin: 0, isTextBox: true });
  d.addText(section.blurb, { x: 0.75, y: 3.3, w: 5.2, h: 0.6, fontFace: FONT, fontSize: 16, color: C.blue, margin: 0, isTextBox: true });
  phone(d, section.steps[0].images[section.steps[0].images.length - 1], 7.3, 0.55, 4.5);
  for (const step of section.steps) stepSlide(section, step);
}

// Privacy
{
  pres.addSection({ title: 'Privacy and tips' });
  const s = pres.addSlide({ masterName: 'CONTENT', sectionTitle: 'Privacy and tips' });
  s.addText(G.privacy.title, { x: 0.5, y: 0.45, w: 5.2, h: 0.7, fontFace: FONT, fontSize: 30, bold: true, color: C.blue, margin: 0, isTextBox: true });
  G.privacy.points.forEach((p, i) => {
    const y = 1.35 + i * 0.9;
    s.addShape(pres.ShapeType.ellipse, { x: 0.5, y: y + 0.05, w: 0.36, h: 0.36, fill: { color: C.lime }, line: { color: C.lime } });
    s.addText('✓', { x: 0.5, y: y + 0.05, w: 0.36, h: 0.36, fontFace: FONT, fontSize: 13, bold: true, color: C.navy, align: 'center', valign: 'middle', margin: 0, isTextBox: true });
    s.addText(p, { x: 1.05, y, w: 4.7, h: 0.8, fontFace: FONT, fontSize: 13, color: C.navy, margin: 0, valign: 'top', isTextBox: true });
  });
  phone(s, G.privacy.image, 7.45, 0.55, 4.25);
}

// Tips
{
  const s = pres.addSlide({ masterName: 'CONTENT', sectionTitle: 'Privacy and tips' });
  s.addText('Good to know', { x: 0.5, y: 0.45, w: 9, h: 0.7, fontFace: FONT, fontSize: 30, bold: true, color: C.blue, margin: 0, isTextBox: true });
  const cw = 4.35, ch = 1.6, gx = 0.3, gy = 0.25;
  G.tips.forEach((t, i) => {
    const x = 0.5 + (i % 2) * (cw + gx);
    const y = 1.35 + Math.floor(i / 2) * (ch + gy);
    s.addShape(pres.ShapeType.roundRect, { x, y, w: cw, h: ch, rectRadius: 0.15, fill: { color: C.tint }, line: { color: C.tint } });
    s.addText(t.title, { x: x + 0.25, y: y + 0.2, w: cw - 0.5, h: 0.4, fontFace: FONT, fontSize: 16, bold: true, color: C.blue, margin: 0, isTextBox: true });
    s.addText(t.text, { x: x + 0.25, y: y + 0.65, w: cw - 0.5, h: 0.8, fontFace: FONT, fontSize: 13, color: C.navy, margin: 0, valign: 'top', isTextBox: true });
  });
}

// Closing
{
  const s = pres.addSlide({ sectionTitle: 'Privacy and tips' });
  s.background = { color: C.blue };
  pills(s, true);
  s.addImage({ path: ICON, x: 4.4, y: 0.9, w: 1.2, h: 1.2, altText: 'Attenlume app icon' });
  s.addText(G.closing, { x: 0.75, y: 2.35, w: 8.5, h: 0.9, fontFace: FONT, fontSize: 36, bold: true, color: C.cream, align: 'center', margin: 0, isTextBox: true });
  s.addText([
    { text: 'Download for Android or Windows', options: { breakLine: true } },
    { text: G.download, options: { bold: true } },
  ], { x: 1.5, y: 3.4, w: 7, h: 0.8, fontFace: FONT, fontSize: 15, color: C.lime, align: 'center', margin: 0, isTextBox: true });
  s.addText('Samlytics Data Services', { x: 1.5, y: 4.55, w: 7, h: 0.3, fontFace: FONT, fontSize: 11, color: C.cream, align: 'center', margin: 0, isTextBox: true });
}

pres.writeFile({ fileName: OUT }).then((f) => console.log('wrote ' + path.resolve(f)));
