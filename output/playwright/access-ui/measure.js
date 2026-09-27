async (page) => {
  await page.addScriptTag({ path: 'C:/Users/hoelk/source/repos/solid-dataspace/solid-dataspace-manager/node_modules/axe-core/axe.min.js' });
  const results = [];
  for (const width of [320, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    await page.waitForTimeout(300); // Let the existing manager sidebar transition settle.
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    const layout = await page.evaluate(() => {
      const root = document.querySelector('.access-inbox');
      const overflowing = Array.from(root.querySelectorAll('*')).filter(element => {
        if (!element.getClientRects().length || element.closest('dialog:not([open])')) return false;
        const rect = element.getBoundingClientRect();
        const bounds = root.getBoundingClientRect();
        return rect.right > bounds.right + 2 || rect.left < bounds.left - 2;
      }).map(element => ({ tag: element.tagName, class: element.className?.baseVal ?? element.className }));
      return { viewport: innerWidth, documentWidth: document.documentElement.scrollWidth, contentWidth: root.clientWidth, overflowing };
    });
    const audit = await page.evaluate(async () => {
      const result = await window.axe.run(document.querySelector('.access-inbox'), { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] } });
      return result.violations.map(item => ({ id: item.id, impact: item.impact, nodes: item.nodes.map(node => node.target) }));
    });
    results.push({ width, layout, violations: audit });
  }
  return results;
}
