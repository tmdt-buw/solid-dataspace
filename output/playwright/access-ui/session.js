export default { info: { webId: 'https://pod.example/alex/profile/card#me' }, fetch: async (url, init) => {
  window.__accessFixtureWrites.push({ type: init?.method || 'GET', url });
  return { ok: true, status: 201 };
} };
