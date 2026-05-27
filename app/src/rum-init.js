import { AwsRum, RRWebPlugin } from 'aws-rum-web';

const APP_MONITOR_ID = window.__RUM_APP_MONITOR_ID__;
const REGION = window.__RUM_REGION__;
const IDENTITY_POOL_ID = window.__RUM_IDENTITY_POOL_ID__;

const config = {
  sessionSampleRate: 1,
  identityPoolId: IDENTITY_POOL_ID,
  endpoint: `https://dataplane.rum.${REGION}.amazonaws.com`,
  telemetries: ['performance', 'errors', ['http', { recordAllRequests: true }]],
  allowCookies: true,
  enableXRay: false,
  sessionEventLimit: 0,
  sessionLengthSeconds: 1800,
  eventPluginsToLoad: [new RRWebPlugin()]
};

try {
  const awsRum = new AwsRum(APP_MONITOR_ID, '1.0.0', REGION, config);
  window.__awsRum = awsRum;
  window.__replayActive = true;
} catch (err) {
  window.__replayActive = false;
}
