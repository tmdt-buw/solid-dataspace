async (page) => {
  await page.locator('.route-workspace').waitFor();
  const results = [];
  for (const width of [320, 390, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.evaluate(() => Promise.all(document.getAnimations().filter(animation => animation instanceof CSSTransition).map(animation => animation.finished.catch(() => {}))));
    const openMap = page.getByRole('button', { name: 'Karte öffnen', exact: true });
    if (await openMap.isVisible()) await openMap.click();
    results.push(await page.evaluate(() => {
      const rect = (selector) => {
        const element = document.querySelector(selector);
        const box = element?.getBoundingClientRect();
        return box ? { x: box.x, y: box.y, width: box.width, height: box.height, bottom: box.bottom, right: box.right } : null;
      };
      const legend = rect('.map-legend'), fit = rect('.fit-route-button'), stats = rect('.map-stats');
      const overlaps = (a,b) => !!a && !!b && a.x < b.right && b.x < a.right && a.y < b.bottom && b.y < a.bottom;
      return { viewport: innerWidth, pageOverflow: document.documentElement.scrollWidth > innerWidth,
        workspace: rect('.route-workspace'), planner: rect('.planner-panel'), map: rect('.map-stage'),
        overlayOverlap: overlaps(legend, fit) || overlaps(legend, stats), zoom: getComputedStyle(document.body).zoom };
    }));
    await page.screenshot({ path: `city-tours-implementation/manager-map-${width}.png`, scale: 'css' });
  }
  return results;
}
