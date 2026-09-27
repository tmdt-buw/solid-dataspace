const params = new URLSearchParams(location.search);
const variant = params.get('case') || 'normal';
const kind = params.get('view') === 'decisions' ? 'decision' : 'request';
const inbox = 'https://pod.example/alex/inbox/';
const owner = 'https://pod.example/alex/';
const run = '11111111-1111-4111-8111-111111111111';
const identifier = 'solid-tours-activity-' + run;
const catalogDocument = owner + 'catalog/ds/' + identifier + '.ttl';
const activity = owner + 'solid-tours/runs/' + run + '/activity.geojson';
const statuses = kind === 'request'
  ? ['pending', 'approved', 'pending', 'approved', 'pending', 'approved', 'denied', 'revoked', 'expired', 'archived']
  : ['approved', 'denied', 'revoked', 'expired', 'archived', 'approved', 'approved', 'approved', 'approved', 'approved'];
const names = ['Nordpark · Wege und Grünflächen', 'Fahrradverkehr im Luisenviertel', 'Settings', 'Luftqualität rund um die Nordbahntrasse', 'Bewegung im Quartier', 'Stadtrundgang durch Elberfeld', 'Mobilität und Stadtklima', 'Routen entlang der Wupper', 'Öffentliche Grünflächen', 'Sprache'];
let items = statuses.map((status, index) => ({
  kind, id: inbox + 'item-' + index,
  requestId: 'request-' + index,
  status, decision: status,
  datasetTitle: names[index], datasetIdentifier: 'dataset-2026-09-' + (index + 1),
  datasetAccessUrl: 'https://research.example/mobility/data/' + index + '.ttl',
  requesterName: index % 2 ? 'Bergische Universität Wuppertal' : 'Hannah Müller',
  requesterEmail: 'hannah.mueller@example.org',
  requesterWebId: 'https://research.example/urban-mobility/research-team/profile/card#me',
  createdAt: new Date(Date.UTC(2026, 8, 26 - index, 9, 30)).toISOString(),
  decidedAt: new Date(Date.UTC(2026, 8, 26 - index, 10, 45)).toISOString(),
  expiresAt: index % 2 ? '2028-12-31T16:00:00Z' : '',
  message: 'Wir möchten die Daten für eine Auswertung zur nachhaltigen Mobilität in Wuppertal verwenden. Vielen Dank für die Unterstützung!',
  decisionComment: status === 'approved' ? 'Für die gemeinsame Auswertung freigegeben.' : 'Bitte stimme den Verwendungszweck vorab mit uns ab.',
}));
if (variant === 'empty') items = [];
if (variant === 'consent' || variant === 'invalid') items = [{
  ...items[0], applicationId: 'environmental-monitoring', applicationName: 'Environmental Monitoring',
  requesterWebId: 'https://worker.example/profile/card#me',
  requestId: '22222222-2222-4222-8222-222222222222', scenarioRunId: run,
  datasetIdentifier: identifier, datasetAccessUrl: activity, catalogDatasetUrl: catalogDocument + '#it',
  requestedModes: ['http://www.w3.org/ns/auth/acl#Read'],
  purpose: variant === 'invalid' ? 'unsupported' : 'completed-route-public-display',
  dataCategory: 'route-and-derived-activity-summary', outputVisibility: 'public', publicationScope: 'dataspace',
}];
window.__accessFixtureWrites = [];
const writes = (type, url) => window.__accessFixtureWrites.push({ type, url });
export async function getSolidDataset(url) {
  if (variant === 'error') throw new Error('Simulated local read failure');
  if (variant === 'loading') return new Promise(() => {});
  if (url.includes('/profile/')) return { profile: true };
  if (url === inbox) return { inbox: true };
  if (url === catalogDocument) return { catalog: true };
  return items.find(item => item.id === url);
}
export const getContainedResourceUrlAll = () => items.map(item => item.id);
export function getThing(dataset, url) {
  if (dataset?.profile) return { inbox };
  if (dataset?.catalog) return { values: url.endsWith('#it') ? {
    'http://purl.org/dc/terms/accessRights': 'restricted', 'http://purl.org/dc/terms/identifier': identifier,
    'http://www.w3.org/ns/dcat#distribution': [catalogDocument + '#distribution'],
  } : { 'http://www.w3.org/ns/dcat#downloadURL': activity, 'http://www.w3.org/ns/dcat#mediaType': 'application/geo+json' } };
  return dataset;
}
export const getThingAll = value => value ? [value] : [];
export const getUrl = (thing, predicate) => thing?.inbox || thing?.values?.[predicate] || '';
export const getUrlAll = (thing, predicate) => thing?.values?.[predicate] || [];
export const getStringNoLocale = (thing, predicate) => thing?.values?.[predicate] || '';
export const getDatetime = () => null;
export const deleteFile = async url => { writes('delete', url); items = items.filter(item => item.id !== url); };
export const saveSolidDatasetAt = async (url, value) => { writes('save', url); items = items.map(item => item.id === url ? value : item); };
export const setStringNoLocale = (thing, predicate, value) => ({ ...thing, [predicate.split('#').pop()]: value });
export const setUrl = setStringNoLocale;
export const setThing = (dataset, thing) => thing;
export const removeAll = (thing, predicate) => { const next = { ...thing }; delete next[predicate.split('#').pop()]; return next; };
export const getFileWithAcl = async url => ({ url });
export const getSolidDatasetWithAcl = getFileWithAcl;
export const getResourceAcl = value => value;
export const hasResourceAcl = () => true;
export const hasAccessibleAcl = () => true;
export const createAclFromFallbackAcl = value => value;
export const setAgentResourceAccess = value => value;
export const saveAclFor = async resource => writes('acl', resource.url);
