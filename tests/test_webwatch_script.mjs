import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
const swift = readFileSync(new URL('../Sources/WebWatch.swift', import.meta.url), 'utf8');
const source = swift.split('static let source = #"""')[1].split('"""#')[0]
  .replace('window.__miraWatch = {', 'window.stableKey = stableKey; window.itemInfo = itemInfo; window.candidateFor = candidateFor; window.__miraWatch = {');
const context = { window: {}, URL, location: { href: 'https://example.edu/work' } };
vm.createContext(context);
vm.runInContext(source, context);
function row(text) {
  return { innerText: text, textContent: text, tagName: 'ARTICLE', classList: [],
    querySelectorAll: () => [], querySelector: () => null };
}
test('deadline label wins over publication date', () => {
  assert.equal(context.window.itemInfo(row('作业一 发布时间 2026-11-10 截止时间：2026-11-20 23:59')).dueText, '2026-11-20 23:59');
});
test('multiple unlabelled dates are not guessed', () => {
  assert.equal(context.window.itemInfo(row('作业一 2026-11-10 2026-11-20')).dueText, '');
});
test('single date and English deadline remain readable', () => {
  assert.equal(context.window.itemInfo(row('作业一 2026-11-20')).dueText, '2026-11-20');
  assert.equal(context.window.itemInfo(row('Published 2026-11-10 Due date: 2026-11-20')).dueText, '2026-11-20');
});
test('one assignment can be a candidate', () => {
  const container = { children: [row('作业一 截止 2026-11-20')], classList: [], tagName: 'SECTION', parentElement: null };
  assert.equal(context.window.candidateFor(container).count, 1);
});

test('assignment ID query parameters distinguish assignments', () => {
  assert.notEqual(context.window.stableKey('https://example.edu/work?workId=1', 'A', ''), context.window.stableKey('https://example.edu/work?workId=2', 'B', ''));
});
