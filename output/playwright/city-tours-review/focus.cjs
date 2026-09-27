async (page) => {
  const read = () => page.evaluate(() => ({
    tag: document.activeElement?.tagName,
    name: document.activeElement?.getAttribute('aria-label') || document.activeElement?.textContent?.trim().slice(0, 80),
    insideDialog: !!document.activeElement?.closest('[role=dialog]'),
    dialogCount: document.querySelectorAll('[role=dialog]').length,
  }));
  const steps = [{ step: 'after open and Escape', ...await read() }];
  for (let i = 0; i < 9; i++) {
    await page.keyboard.press('Tab');
    steps.push({ step: `Tab ${i + 1}`, ...await read() });
  }
  return steps;
}
