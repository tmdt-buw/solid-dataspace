async (page) => page.evaluate(() => {
  const dialog = document.querySelector('dialog');
  return { open: dialog.open, modal: dialog.matches(':modal'), labels: dialog.getAttribute('aria-labelledby'), title: document.getElementById(dialog.getAttribute('aria-labelledby'))?.textContent, focusTag: document.activeElement.tagName, focusName: document.activeElement.getAttribute('aria-label') || document.activeElement.textContent.trim().slice(0, 60), attributes: dialog.outerHTML.slice(0, 550) };
})
