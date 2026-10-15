// A Highball tool whose engine cannot run a renderer does not offer it, and a game still
// set to that renderer shows Automatic. Other tools keep the full list.
'use strict';
const { panel, walk, details, runner, FORMS } = require('./harness');

const emit = process.argv[2];
if (!emit) { console.error('usage: renderer-gaps.js <emit>'); process.exit(2); }

const HB = 'protonish-highball-x64-crossover26.3-r19';

let failed = 0;
for (const form of Object.keys(FORMS)) {
  const { render: P } = panel(emit, form, undefined, { noD3DMetal: [HB], noDXVK: [HB] });
  const t = runner(`${form}, renderer gaps`);
  const nodes = (opts, tool) => walk(P({ details: details(opts + ' %command%', { strCompatToolName: tool }) }));
  const dropdown = ns => ns.find(x => x.type === 'Dropdown' && x.props.rgOptions.some(o => o.data === 'wined3d'));
  const backends = ns => dropdown(ns).props.rgOptions.map(o => o.data);
  const toggles = ns => ns.filter(x => x.type === 'Toggle').map(x => x.props.label);

  let r = nodes('', HB);
  t.ok(!backends(r).includes('d3dmetal') && !backends(r).includes('dxvk'),
       `the Highball tool offers neither D3DMetal nor DXVK (${backends(r)})`);
  t.ok(backends(r).includes('dxmt') && backends(r).includes('wined3d'), 'DXMT and WineD3D stay');
  r = nodes('CX_GRAPHICS_BACKEND=d3dmetal', HB);
  t.ok(dropdown(r).props.selectedOption === '', 'a game set to the missing D3DMetal shows Automatic');
  t.ok(!toggles(r).includes('DLSS'), 'the D3DMetal DLSS row is hidden with it');
  r = nodes('CX_GRAPHICS_BACKEND=dxvk', HB);
  t.ok(dropdown(r).props.selectedOption === '', 'a game set to the missing DXVK shows Automatic');

  r = nodes('', 'protonish-26.3');
  t.ok(backends(r).includes('d3dmetal') && backends(r).includes('dxvk'), 'a CrossOver tool keeps every renderer');
  r = nodes('CX_GRAPHICS_BACKEND=d3dmetal', 'protonish-26.3');
  t.ok(dropdown(r).props.selectedOption === 'd3dmetal', 'a CrossOver game keeps its D3DMetal choice');

  const { render: Q } = panel(emit, form);
  r = walk(Q({ details: details(' %command%', { strCompatToolName: HB }) }));
  t.ok(backends(r).includes('d3dmetal') && backends(r).includes('dxvk'), 'without gaps the Highball tool offers everything');
  failed += t.done();
}
process.exit(failed ? 1 : 0);
