# Post-Mortem - DLQ Incident

## Summary

A processing failure caused messages to be retried multiple times and eventually moved to the Dead Letter Queue (DLQ).

The incident was successfully detected through CloudWatch alarms and an SNS email notification.

## Timeline

| Time | Event                                    |
| ---- | ---------------------------------------- |
| T+00 | Event received by API Gateway            |
| T+01 | Event sent to SQS                        |
| T+02 | Processor Lambda failed during execution |
| T+03 | SQS retried message delivery             |
| T+04 | Message exceeded retry limit             |
| T+05 | Message moved to DLQ                     |
| T+06 | CloudWatch alarm entered ALARM state     |
| T+07 | SNS notification email received          |
| T+08 | Investigation started                    |

## Impact

- The event was not processed successfully.
- No record was persisted to DynamoDB.
- The message was isolated in the DLQ.
- No data was lost.

## Detection

The incident was detected through:

- CloudWatch Metrics
- CloudWatch Alarm
- SNS Email Notification

## Root Cause

The processor Lambda encountered a simulated transient failure.

As a result, all retry attempts failed and the message was moved to the Dead Letter Queue.

## Resolution

The failure condition was removed.

The root cause was validated through CloudWatch Logs.

The message could then be replayed from the DLQ if necessary.

## Lessons Learned

- DLQ isolates failed messages for investigation or replay.
- CloudWatch alarms provide fast detection.
- SNS notifications reduce response time.
- Retry mechanisms alone are not sufficient for permanent failures.
- Operational visibility is critical for distributed systems.

## Preventive Actions

- Continue monitoring DLQ depth.
- Review processor error logs regularly.
- Maintain alarm coverage for critical components.
- Document recovery procedures in runbooks.
