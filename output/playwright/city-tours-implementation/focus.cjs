async (page) => {
  if (!await page.locator('dialog[open]').count()) {
    await page.getByRole('button', { name: 'Als absolviert eintragen', exact: true }).click();
  }
  await page.screenshot({ path: 'city-tours-implementation/manager-completion-desktop.png', scale: 'css' });
  const start = await page.evaluate(() => ({ active: document.activeElement?.outerHTML, dialog: document.querySelector('dialog')?.outerHTML.slice(0, 500), modal: document.querySelector('dialog')?.matches(':modal') }));
  const outside = [];
  for (let i = 0; i < 24; i++) {
    await page.keyboard.press('Tab');
    if (!await page.evaluate(() => Boolean(document.activeElement?.closest('dialog')))) outside.push(i);
  }
  await page.keyboard.press('Escape');
  const end = await page.evaluate(() => ({ dialogClosed: !document.querySelector('dialog[open]'), returnedTo: document.activeElement?.textContent }));
  return { start, outside, end };
}
