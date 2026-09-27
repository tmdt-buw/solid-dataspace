async (page) => {
  await page.setViewportSize({ width: 320, height: 900 });
  await page.waitForTimeout(300);
  await page.addScriptTag({ path: 'C:/Users/hoelk/source/repos/solid-dataspace/solid-dataspace-manager/node_modules/axe-core/axe.min.js' });
  const state = await page.evaluate(() => {
    const root = document.querySelector('.access-inbox');
    const bounds = root.getBoundingClientRect();
    const overflowing = Array.from(root.querySelectorAll('*')).filter(element => {
      if (!element.getClientRects().length || element.closest('dialog:not([open])')) return false;
      // The loading animation travels beyond its rail and is intentionally clipped.
      if (element.parentElement?.classList.contains('dataspace-content-loading__rail')) return false;
      const rect = element.getBoundingClientRect();
      return rect.right > bounds.right + 2 || rect.left < bounds.left - 2;
    }).map(element => element.tagName + '.' + element.className);
    return {
      url: location.search, heading: root.querySelector('h1')?.textContent, headings: root.querySelectorAll('h1').length,
      overflow: overflowing,
      actions: Array.from(root.querySelectorAll('.notification-buttons button')).map(button => ({ label: button.textContent.trim(), disabled: button.disabled })),
      alerts: Array.from(root.querySelectorAll('[role="alert"]')).map(node => node.textContent),
      empty: Boolean(root.querySelector('.notifications-empty')),
      loading: Boolean(root.querySelector('[aria-busy="true"]')),
      consentNoticeLength: root.querySelector('.notification-consent__notice p')?.textContent.length || 0,
      writes: window.__accessFixtureWrites,
    };
  });
  const violations = await page.evaluate(async () => (await window.axe.run(document.querySelector('.access-inbox'), { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] } })).violations.map(item => ({ id: item.id, nodes: item.nodes.map(node => node.target) })));
  return { ...state, violations };
}
