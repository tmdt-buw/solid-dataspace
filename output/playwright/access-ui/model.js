export * from '../../../../solid-dataspace-manager/src/accessRequestModel.js';
export const parseAccessRequestThing = (url, thing) => thing?.kind === 'request' ? thing : null;
export const parseAccessDecisionThing = (url, thing) => thing?.kind === 'decision' ? thing : null;
