# Ingestion Failure Runbook

Owner: Platform SRE / Ingestion Team
Severity: High
Escalation: Escalate to SRE Lead if not resolved within 30 minutes

## Alert

- CloudWatch alarm or dashboard spike for 5xx API errors affecting the ingestion endpoint.
- `ingestion EventFailed` metric increase or `Total Failures` single-value alert.

## Symptoms

- Clients receive HTTP 500 responses with a `correlationId` in the body.
- CloudWatch logs for the `ingestion` service show `Ingestion Failure` errors and matching `correlationId`.
- Event Flow dashboard shows a spike in 5xx errors and `EventFailed` count.

## Investigation Steps

1. Record the alarm timestamp and any `correlationId` from the client response (image 01).
2. Search ingestion logs in CloudWatch for the `correlationId` and timestamp to obtain stack traces and context.

   Example (replace values):

   ```powershell
   $id = "<correlationId>"
   aws logs filter-log-events --log-group-name /aws/lambda/ingestion --filter-pattern "\"correlationId\": \"$id\"" --region us-east-2
   ```

3. Check ingestion metrics: `EventIngested`, `EventFailed`, and API 5xx counts on the dashboard around the timestamp.
4. Verify downstream dependencies (DynamoDB, external APIs) for errors or throttling at the same time.
5. Check Lambda concurrency and recent deployments (`aws lambda get-function-configuration --function-name <ingestion-fn>`).

## How to Reproduce

1. Use the example payload from `docs/incidents/ingestion-failure.md` with `forceIngestionFailure: true` and POST it to the ingestion API endpoint:

```bash
curl -X POST https://<INGESTION_API_URL>/ingest \
	-H "Content-Type: application/json" \
	-d '{"eventId":"test-123","eventName":"Order Created","eventType":"OrderCreated","forceIngestionFailure":true,"payload":{"order_id":"order-test","customer_id":"cust-test","amount":1.0,"currency":"USD"}}'
```

2. Observe the API response and check CloudWatch logs for the `correlationId` returned.

Alternative: If direct API access is not available, reproduce by invoking the ingestion Lambda in a test environment or running a controlled request through the same integration used by clients.

## Verification

1. Confirm the ingestion API returns HTTP 200 for valid test requests and provides a `correlationId`.
2. Confirm `EventFailed` metric returns to baseline and the 5xx spike clears in the dashboard.
3. Confirm events are queued (check `EventIngested` metric) and downstream processors receive the events.

If the issue persists, collect logs, sample request/response, and metric history and escalate to the SRE lead with timestamps and `correlationId`.
