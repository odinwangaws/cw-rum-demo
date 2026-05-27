#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-cw-rum-demo}"
REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${2:-localhost}"

echo "=== CloudWatch RUM Demo Setup ==="
echo "Stack:  $STACK_NAME"
echo "Region: $REGION"
echo "Domain: $DOMAIN"
echo ""

# Deploy CloudFormation stack
echo "[1/5] Deploying infrastructure..."
aws cloudformation deploy \
  --template-file infra/template.yaml \
  --stack-name "$STACK_NAME" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AppName="$STACK_NAME" Domain="$DOMAIN" \
  --region "$REGION"

# Get outputs
echo "[2/5] Retrieving configuration..."
OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs' \
  --output json)

APP_MONITOR_ID=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(next(o['OutputValue'] for o in json.load(sys.stdin) if o['OutputKey']=='AppMonitorId'))")
IDENTITY_POOL_ID=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(next(o['OutputValue'] for o in json.load(sys.stdin) if o['OutputKey']=='IdentityPoolId'))")
CONSOLE_URL=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(next(o['OutputValue'] for o in json.load(sys.stdin) if o['OutputKey']=='ConsoleUrl'))")

# Build session replay bundle
echo "[3/5] Building RUM bundle (includes Session Replay)..."
(cd app && npm install --silent \
  && sed -i.bak 's/maskAllInputs: true/maskAllInputs: false/' node_modules/@aws-rum/web-core/dist/es/plugins/event-plugins/RRWebPlugin.js \
  && python3 -c "
f='node_modules/@aws-rum/web-core/dist/es/plugins/event-plugins/RRWebPlugin.js'
c=open(f).read()
old='''const ENFORCED_PRIVACY_OPTIONS = {
    maskAllInputs: false,
    maskTextSelector: '*',
    maskInputOptions: undefined
};'''
new='''const ENFORCED_PRIVACY_OPTIONS = {
    maskAllInputs: false,
    maskTextSelector: '[data-rum-mask]',
    maskInputOptions: { text: true, email: true, password: true, tel: true, url: true, search: true, number: true, textarea: true, select: true },
    maskInputFn: (text, element) => {
        if (element && element.hasAttribute && element.hasAttribute('data-rum-mask')) {
            return '*'.repeat(text.length);
        }
        return text;
    }
};'''
open(f,'w').write(c.replace(old,new))
print('      Patched selective masking')
" \
  && npx esbuild src/rum-init.js --bundle --format=iife --target=es2020 --outfile=dist/rum-bundle.js --minify)

# Generate index.html from template
echo "[4/5] Generating demo page..."
sed -e "s|{{APP_MONITOR_ID}}|$APP_MONITOR_ID|g" \
    -e "s|{{IDENTITY_POOL_ID}}|$IDENTITY_POOL_ID|g" \
    -e "s|{{REGION}}|$REGION|g" \
    -e "s|{{STACK_NAME}}|$STACK_NAME|g" \
    app/index.template.html > app/index.html

echo "[5/5] Configuring console features..."
# Enable CustomEvents on App Monitor (required for session replay)
aws rum update-app-monitor --name "$STACK_NAME" --region "$REGION" --custom-events Status=ENABLED >/dev/null 2>&1 || true

# Enable extended metrics (populates the Metrics tab in console)
aws rum put-rum-metrics-destination --app-monitor-name "$STACK_NAME" --region "$REGION" --destination CloudWatch >/dev/null 2>&1 || true
aws rum batch-create-rum-metric-definitions --app-monitor-name "$STACK_NAME" --region "$REGION" --destination CloudWatch --metric-definitions \
  "[{\"Name\":\"PageViewCount\",\"EventPattern\":\"{\\\"event_type\\\":[\\\"com.amazon.rum.page_view_event\\\"],\\\"metadata\\\":{\\\"pageId\\\":[\\\"*\\\"]}}\",\"DimensionKeys\":{\"metadata.pageId\":\"PageId\"}},
    {\"Name\":\"JsErrorCount\",\"EventPattern\":\"{\\\"event_type\\\":[\\\"com.amazon.rum.js_error_event\\\"],\\\"metadata\\\":{\\\"pageId\\\":[\\\"*\\\"]}}\",\"DimensionKeys\":{\"metadata.pageId\":\"PageId\"}},
    {\"Name\":\"Http4xxCount\",\"EventPattern\":\"{\\\"event_type\\\":[\\\"com.amazon.rum.http_event\\\"],\\\"metadata\\\":{\\\"pageId\\\":[\\\"*\\\"]}}\",\"DimensionKeys\":{\"metadata.pageId\":\"PageId\"}},
    {\"Name\":\"Http5xxCount\",\"EventPattern\":\"{\\\"event_type\\\":[\\\"com.amazon.rum.http_event\\\"],\\\"metadata\\\":{\\\"pageId\\\":[\\\"*\\\"]}}\",\"DimensionKeys\":{\"metadata.pageId\":\"PageId\"}}]" >/dev/null 2>&1 || true

# Seed User Journey data (multiple sessions with navigation paths)
echo "      Seeding User Journey data..."
python3 -c "
import boto3, uuid, time, json
client = boto3.client('rum', region_name='$REGION')
JOURNEYS = [
    ['/','/dashboard','/settings','/dashboard'],
    ['/','/dashboard','/checkout'],
    ['/','/settings','/'],
    ['/','/dashboard','/settings','/checkout'],
    ['/','/checkout'],
    ['/','/dashboard','/checkout'],
    ['/','/settings','/checkout'],
    ['/','/dashboard'],
]
now_ms = int(time.time() * 1000)
for i, journey in enumerate(JOURNEYS):
    session_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    rum_events = []
    for j, page in enumerate(journey):
        event_ts = now_ms - (len(JOURNEYS)-i)*60000 + j*5000
        parent = f'{journey[j-1]}-{j-1}' if j > 0 else ''
        rum_events.append({
            'id': str(uuid.uuid4()),
            'timestamp': event_ts/1000.0,
            'type': 'com.amazon.rum.page_view_event',
            'metadata': json.dumps({'version':'1.0.0','browserName':'Chrome','browserVersion':'148','osName':'macOS','deviceType':'desktop','platformType':'web','pageId':page}),
            'details': json.dumps({'version':'1.0.0','pageId':page,'pageInteractionId':f'{page}-{j}','interaction':j,'parentPageInteractionId':parent})
        })
    client.put_rum_events(
        Id='$APP_MONITOR_ID', BatchId=str(uuid.uuid4()),
        AppMonitorDetails={'id':'$APP_MONITOR_ID','version':'1.0.0'},
        UserDetails={'sessionId':session_id,'userId':user_id},
        RumEvents=rum_events
    )
print('  Done — 8 sessions seeded')
" 2>/dev/null || echo "      (seed skipped — not critical)"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "  App Monitor ID:    $APP_MONITOR_ID"
echo "  Identity Pool ID:  $IDENTITY_POOL_ID"
echo "  Region:            $REGION"
echo ""
echo "  Console Dashboard: $CONSOLE_URL"
echo ""
echo "  To start the demo:"
echo "    cd app && python3 -m http.server 8888"
echo "    open http://localhost:8888"
echo ""
