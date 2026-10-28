// Builds the printable A4 HTML for the Attenlume quick guide; Edge prints it to PDF.
const fs = require('fs');
const G = require('./content');

const REPO = require('path').resolve(__dirname, '..', '..').replace(/\\/g, '/');
const ASSETS = `file:///${REPO}/assets`;
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const phone = (name) =>
  `<figure class="phone"><img src="${ASSETS}/guide/${name}.jpg" alt="Attenlume screen: ${esc(name.replace(/^\d+-/, '').replace(/-/g, ' '))}"></figure>`;

let stepNo = 0;
const step = (s) => {
  stepNo++;
  return `
  <section class="step">
    <div class="step-text">
      <p class="step-no">Step ${stepNo}</p>
      <h3>${esc(s.title)}</h3>
      <ol>${s.points.map((p) => `<li>${esc(p)}</li>`).join('')}</ol>
    </div>
    <div class="phones n${s.images.length}">${s.images.map(phone).join('')}</div>
  </section>`;
};

const html = `<!doctype html>
<html lang="en-GB"><head><meta charset="utf-8">
<title>${esc(G.title)}</title>
<style>
@font-face { font-family: Montserrat; font-weight: 400; src: url(${ASSETS}/fonts/Montserrat-Regular.ttf); }
@font-face { font-family: Montserrat; font-weight: 500; src: url(${ASSETS}/fonts/Montserrat-Medium.ttf); }
@font-face { font-family: Montserrat; font-weight: 600; src: url(${ASSETS}/fonts/Montserrat-SemiBold.ttf); }
@font-face { font-family: Montserrat; font-weight: 700; src: url(${ASSETS}/fonts/Montserrat-Bold.ttf); }
:root { --blue:#4392F1; --navy:#00212B; --cream:#FEFFF8; --lime:#DCFF38; --tint:#EAF2FD; --muted:#4A5B60; }
@page { size: A4; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--cream); color: var(--navy); font-family: Montserrat, Calibri, sans-serif; font-size: 10.5pt; line-height: 1.5; }
.page { width: 210mm; height: 297mm; padding: 16mm 16mm 14mm; position: relative; overflow: hidden; page-break-after: always; }
.page:last-child { page-break-after: auto; }
.footer { position: absolute; left: 16mm; right: 16mm; bottom: 8mm; display: flex; justify-content: space-between; font-size: 8pt; color: var(--muted); }
h1, h2, h3 { margin: 0; line-height: 1.15; }
h2 { color: var(--blue); font-size: 22pt; font-weight: 700; margin-bottom: 4mm; }
h3 { color: var(--blue); font-size: 15pt; font-weight: 700; margin: 1mm 0 3mm; }
.chip { display: inline-block; background: var(--lime); color: var(--navy); font-weight: 700; font-size: 9pt; padding: 1.2mm 4mm; border-radius: 99px; margin-bottom: 3mm; }
.blurb { color: var(--muted); font-size: 11pt; margin: -2mm 0 6mm; }

/* Cover */
.cover { background: var(--blue); color: var(--cream); display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; }
.cover .brand { position: absolute; top: 14mm; left: 16mm; font-size: 9.5pt; }
.cover img.icon { width: 34mm; height: 34mm; margin-bottom: 9mm; }
.cover h1 { font-size: 36pt; font-weight: 700; }
.cover .sub { color: var(--lime); font-size: 14pt; font-weight: 500; max-width: 140mm; margin: 6mm auto 0; }
.cover .phones { margin-top: 14mm; } .cover .phone img { width: 38mm; }
.pill { position: absolute; border-radius: 99px; transform: rotate(30deg); }

/* Overview */
.overview { display: grid; grid-template-columns: repeat(4, 1fr); gap: 4mm; margin: 6mm 0 10mm; }
.card { background: var(--blue); color: var(--cream); border-radius: 4mm; padding: 5mm 4mm; min-height: 44mm; }
.card .num { display: inline-flex; width: 9mm; height: 9mm; border-radius: 50%; background: var(--lime); color: var(--navy); font-weight: 700; align-items: center; justify-content: center; margin-bottom: 4mm; }
.card b { display: block; font-size: 12.5pt; margin-bottom: 1.5mm; }
.card span { font-size: 9.5pt; }
.intro { font-size: 11.5pt; max-width: 165mm; }

/* Steps */
.step { display: flex; gap: 8mm; align-items: flex-start; margin-bottom: 11mm; break-inside: avoid; }
.step-text { flex: 1; }
.step-no { margin: 0; color: var(--muted); font-size: 8.5pt; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; }
ol { margin: 0; padding-left: 5.5mm; }
li { margin-bottom: 2.2mm; }
.phones { display: flex; gap: 4mm; flex-shrink: 0; }
.phone { margin: 0; background: var(--navy); padding: 1.6mm; border-radius: 4.5mm; box-shadow: 0 1.5mm 4mm rgba(0,0,0,.15); }
.phone img { display: block; width: 46mm; height: auto; border-radius: 3mm; }

/* Privacy and tips */
.checks { list-style: none; padding: 0; margin: 0; }
.checks li { position: relative; padding-left: 9mm; margin-bottom: 4mm; }
.checks li::before { content: '\\2713'; position: absolute; left: 0; top: .2mm; width: 6mm; height: 6mm; border-radius: 50%; background: var(--lime); font-weight: 700; display: flex; align-items: center; justify-content: center; font-size: 9pt; }
.tips { display: grid; grid-template-columns: 1fr 1fr; gap: 4mm; margin-top: 4mm; }
.tip { background: var(--tint); border-radius: 4mm; padding: 5mm; }
.tip b { color: var(--blue); display: block; font-size: 11.5pt; margin-bottom: 1.5mm; }
.closing { margin-top: 10mm; background: var(--navy); color: var(--cream); border-radius: 4mm; padding: 7mm; text-align: center; }
.closing p { margin: 0; }
.closing .big { font-size: 16pt; font-weight: 700; margin-bottom: 2mm; }
.closing .link { color: var(--lime); font-weight: 600; }
</style></head>
<body>

<div class="page cover">
  <div class="pill" style="width:70mm;height:16mm;background:var(--cream);top:-6mm;right:-14mm"></div>
  <div class="pill" style="width:40mm;height:11mm;background:var(--lime);top:16mm;right:-6mm"></div>
  <div class="pill" style="width:56mm;height:13mm;background:var(--lime);bottom:4mm;left:-16mm"></div>
  <p class="brand">Samlytics Data Services</p>
  <img class="icon" src="${ASSETS}/brand/icons/attenlume-app-icon-filled.png" alt="Attenlume app icon">
  <h1>${esc(G.title)}</h1>
  <p class="sub">${esc(G.subtitle)}</p>
  <div class="phones">${phone('05-recording')}${phone('08-camera')}${phone('15-share')}</div>
</div>

<div class="page">
  <h2>Four steps, one tidy package</h2>
  <p class="intro">${esc(G.intro)}</p>
  <div class="overview">${G.overview.map((o) => `<div class="card"><span class="num">${o.n}</span><b>${esc(o.title)}</b><span>${esc(o.text)}</span></div>`).join('')}</div>
  <span class="chip">1  ${esc(G.sections[0].title)}</span>
  <p class="blurb">${esc(G.sections[0].blurb)}</p>
  ${step(G.sections[0].steps[0])}
  <div class="footer"><span>${esc(G.title)}</span><span>Samlytics Data Services</span></div>
</div>

${(() => {
  // Lay the remaining steps out two per page, starting each section with its chip.
  const pages = [];
  let current = [];
  const flat = [];
  G.sections.forEach((sec, si) => sec.steps.forEach((st, ti) => {
    if (si === 0 && ti === 0) return;
    flat.push({ sec, st, first: ti === 0 });
  }));
  flat.forEach((f) => {
    const head = f.first ? `<span class="chip">${f.sec.n}  ${esc(f.sec.title)}</span><p class="blurb">${esc(f.sec.blurb)}</p>` : '';
    current.push(head + step(f.st));
    if (current.length === 2) { pages.push(current); current = []; }
  });
  if (current.length) pages.push(current);
  return pages.map((p) => `<div class="page">${p.join('')}<div class="footer"><span>${esc(G.title)}</span><span>Samlytics Data Services</span></div></div>`).join('\n');
})()}

<div class="page">
  <section class="step">
    <div class="step-text">
      <h2>${esc(G.privacy.title)}</h2>
      <ul class="checks">${G.privacy.points.map((p) => `<li>${esc(p)}</li>`).join('')}</ul>
    </div>
    <div class="phones">${phone(G.privacy.image)}</div>
  </section>
  <h2 style="margin-top:4mm">Good to know</h2>
  <div class="tips">${G.tips.map((t) => `<div class="tip"><b>${esc(t.title)}</b>${esc(t.text)}</div>`).join('')}</div>
  <div class="closing"><p class="big">${esc(G.closing)}</p><p>Download for Android or Windows: <span class="link">${esc(G.download)}</span></p></div>
  <div class="footer"><span>${esc(G.title)}</span><span>Samlytics Data Services</span></div>
</div>

</body></html>`;

fs.writeFileSync(process.argv[2] || 'guide.html', html, 'utf8');
console.log('wrote html');
