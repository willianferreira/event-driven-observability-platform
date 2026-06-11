# DLQ Incident Runbook

Owner: Platform SRE
Severity: High
Escalation: Escalate to SRE Lead if not resolved within 30 minutes

## Alert

- CloudWatch alarm `event-driven-observability-platform-dlq-depth` triggers (DLQ depth > 0).
- Dashboard shows non-zero or unexpected "Unresolved Events" in the Event Flow & Unresolved Events panel, while DLQ depth is tracked separately.

## Symptoms

- Messages accumulate in the DLQ `event-driven-observability-platform-events-dlq`.
- Processor logs show repeated transient exceptions and `EventRetried` emissions.
- Downstream business processing (orders, notifications) is incomplete.

## Investigation Steps

1. Confirm the DLQ URL and current message count:

```powershell
$queueUrl = (aws sqs get-queue-url --queue-name event-driven-observability-platform-events-dlq --region us-east-2 --query "QueueUrl" --output text)
aws sqs get-queue-attributes --queue-url $queueUrl --attribute-names ApproximateNumberOfMessages --region us-east-2 --query "Attributes.ApproximateNumberOfMessages" --output text
```

2. Check the CloudWatch alarm state and recent evaluation history in the AWS Console for `event-driven-observability-platform-dlq-depth`.

3. Inspect `processor` Lambda logs in CloudWatch for exceptions and correlation IDs. Search for `EventRetried` and stack traces.

4. If errors indicate throttling, DynamoDB conditional failures, or external service timeouts, gather recent error messages, timestamps, and correlation IDs for escalation.

5. If DLQ depth is > 0, sample a message body for analysis:

```powershell
aws sqs receive-message --queue-url $queueUrl --max-number-of-messages 1 --region us-east-2 --visibility-timeout 30 --wait-time-seconds 2 --output json
```

Do not delete messages unless you are certain they are safe to discard; prefer copying the body to a secure location for analysis.

## How to Reproduce

1. Use the example event in `docs/incidents/dlq-incident.md` (set `failTransient: true`) and send it to the ingestion queue:

```powershell
$ingestQueueUrl = (aws sqs get-queue-url --queue-name event-driven-observability-platform-events --region us-east-2 --query "QueueUrl" --output text)
aws sqs send-message --queue-url $ingestQueueUrl --message-body '{"eventId":"test-123","eventName":"Order Created","eventType":"OrderCreated","failTransient":true,"payload":{"order_id":"order-test","customer_id":"cust-test","amount":1.0,"currency":"USD"}}' --region us-east-2
```

2. Observe the `processor` logs for retries and confirm the message moves to the DLQ after `maxReceiveCount` is exceeded.

## Verification

1. Verify DLQ depth returns to expected baseline (zero or acceptable value).
2. Confirm the DLQ depth widget reflects the current DLQ backlog using `ApproximateNumberOfMessagesVisible`.
3. Confirm Event Flow dashboard shows `Unresolved Events` without subtracting `EventRetried`, because retries are an intermediate operational signal.
4. Validate that business downstream systems processed a re-ingested or fixed event as expected.

If the issue persists, collect logs, message samples, and metric history and escalate to the SRE lead with timestamps and correlation IDs.
