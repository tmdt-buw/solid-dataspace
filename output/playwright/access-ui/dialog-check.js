async (page) => {
  await page.addScriptTag({ path: 'C:/Users/hoelk/source/repos/solid-dataspace/solid-dataspace-manager/node_modules/axe-core/axe.min.js' });
  const focus = [];
  for (let i = 0; i < 8; i += 1) {
    focus.push(await page.evaluate(() => ({ name: document.activeElement.getAttribute('aria-label') || document.activeElement.textContent.trim(), inside: Boolean(document.activeElement.closest('dialog[open]')) })));
    await page.keyboard.press('Tab');
  }
  const violations = await page.evaluate(async () => (await window.axe.run(document.querySelector('dialog[open]'), { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] } })).violations.map(item => item.id));
  return { focus, violations, writes: await page.evaluate(() => window.__accessFixtureWrites) };
}
