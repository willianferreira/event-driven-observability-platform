# Schema Violation Runbook

Owner: Ingestion team
Severity: Medium
Escalation: Escalate to Backend team lead if unresolved after 30 minutes

## Alert

- CloudWatch API 4xx errors and schema violation alarms spike

## Symptoms

- Check CloudWatch for schema violation alarms (spike)
- Review the ingestion logs for schema violation errors
- Events not being ingested

## Investigation Steps

- Verify the CloudWatch alarms for schema violation incidents
- Check the ingestion logs for specific schema violation errors
- Identify the producer sending invalid events
- Review the event schema against the expected schema
- Confirm if all required fields are present in the event

## How to Reproduce

Send an invalid event to the API (missing `eventId` or `eventType`). Example:

```bash
curl -i -X POST "https://<api-url>/events" \
  -H "Content-Type: application/json" \
  -d '{ "eventName":"Order Created", "event":"OrderCreated", "payload": { "order_id":"order_123","customer_id":"customer_123","amount":149.9,"currency":"USD" } }'
```

Expected: API returns HTTP 400 and ingestion logs contain `SchemaViolation` / `EventRejected`.

## Verification

- The invalid request returns HTTP 400 (Bad Request)
- Logs contain `SchemaViolation` or `EventRejected` entries for the correlationId
- No message is sent to SQS (check queue depth/messages)
- No record exists in the `orders` DynamoDB table for the invalid event
- After producer fixes the payload, a corrected request should return HTTP 200, events should be queued and processed

### Logs Insights example

```sql
fields @timestamp, @message
| filter @message like /SchemaViolation/ or @message like /EventRejected/
| sort @timestamp desc
| limit 50
```

\*\*\* End of runbook
