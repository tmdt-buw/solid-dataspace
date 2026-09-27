async (page) => {
  const results = [];
  for (const width of [320, 390, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    results.push(await page.evaluate(() => ({
      viewport: window.innerWidth,
      elements: Array.from(document.querySelectorAll('.route-workspace,.planner-panel,.map-stage,.map-stats,.map-legend')).map(el => {
        const r = el.getBoundingClientRect();
        return { element: el.className, width: r.width, height: r.height, left: r.left, right: r.right };
      }),
      importDisplay: getComputedStyle(document.querySelector('input[type=file]')).display,
    })));
  }
  return results;
}
