async (page) => {
  const results = [];
  for (const screen of ['login', 'onboarding', 'sharing-setup']) {
    await page.goto(`http://127.0.0.1:4306/?screen=${screen}`);
    await page.locator(screen === 'login' ? '.city-tours-login' : '.tours-onboarding').waitFor();
    for (const width of [320, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      results.push(await page.evaluate(({ screen }) => ({
        screen, width: innerWidth, pageOverflow: document.documentElement.scrollWidth > innerWidth,
        checkboxes: document.querySelectorAll('input[type="checkbox"]').length,
        publicIdentityFields: document.querySelectorAll('input[name="city-tours-publisher"], input[name="city-tours-contact-email"]').length,
      }), { screen }));
      await page.screenshot({ path: `city-tours-implementation/${screen}-${width}.png`, fullPage: true, scale: 'css' });
    }
  }
  return results;
}
