const { JSDOM } = require('jsdom');
const dom = new JSDOM('<!doctype html><body></body>', { pretendToBeVisual: true, url: 'http://localhost/' });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Event', 'MouseEvent', 'KeyboardEvent', 'Node', 'getComputedStyle', 'requestAnimationFrame']) {
  try { Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true }); } catch { /* ya definido */ }
}
require('./.out/mtest.cjs');
