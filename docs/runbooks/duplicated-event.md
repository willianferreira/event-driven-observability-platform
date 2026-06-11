# Duplicated Event (Idempotency) Runbook

Owner: Processing team
Severity: Medium
Escalation: Escalate to Backend team lead if the pipeline keeps receiving duplicated events

## Alert

- Elevated duplicated-event rate (%) or mismatch between ingested and processed counts (dashboard/CloudWatch).

## Symptoms

- Spike in duplicated-event rate on the dashboard
- CloudWatch/processor logs show idempotency or duplicate-detection messages (e.g., `Idempotency: Duplicated Message ignored`)
- No duplicate messages processed downstream, but processor count increases
- Possible downstream side-effects (billing, BI inconsistency)

## Investigation Steps

- Verify CloudWatch metrics and alarms for duplicated events
- Capture sample `eventId`(s) and timestamps from the dashboard
- Search processing and API logs for the sample `eventId`(s) and correlationId to confirm duplicate detection
- Check the idempotency store (DynamoDB) for the `eventId`:

## How to Reproduce

Send the same event twice (example):

```bash
curl -i -X POST "https://<api-url>/events" \
	-H "Content-Type: application/json" \
	-d '{
		"eventId":"123456SameEventId",
		"eventName":"Order Created",
		"eventType":"OrderCreated",
		"payload": { "order_id":"order_123", "customer_id":"customer_123", "amount":149.9, "currency":"USD" }
	}'

# Repeat the same request immediately
```

Expected: first request returns HTTP 202 and message is enqueued; repeated request(s) return HTTP 202, SQS queue receives the event, but processor detects duplicates and skips processing, reflected in CloudWatch metrics and dashboard counts.

## Verification

- CloudWatch shows duplicated-event metric and dashboard reflects mismatch between ingested/processed counts
- Logs contain `Idempotency: Duplicated Message ignored` entries for the correlationId
- `aws dynamodb get-item` returns an idempotency record for the `eventId`
- No additional order record or downstream side effect is created for the duplicated `eventId`

\*\*\* End of runbook
