const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { emitMetric } = require("../../shared/metrics");

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.IDEMPOTENCY_TABLE_NAME;

const REQUIRED_FIELDS = ["eventId", "eventName", "eventType", "payload"];

function validateNormalizedEvent(body) {
  const missing = [];

  for (const field of REQUIRED_FIELDS) {
    if (body[field] == null) missing.push(field);
  }

  if (body.payload != null && typeof body.payload !== "object") {
    missing.push("payload (must be object)");
  }

  return missing;
}

exports.handler = async (event) => {
  const failures = [];

  for (const record of event.Records) {
    const messageId = record.messageId;
    let correlationId = null;

    try {
      const body = JSON.parse(record.body);
      correlationId = body._metadata?.correlationId ?? null;

      const missingFields = validateNormalizedEvent(body);
      if (missingFields.length > 0) {
        console.warn(
          JSON.stringify({
            level: "WARN",
            messageId,
            correlationId,
            reason: "SchemaViolation",
            missingFields,
          }),
        );
        emitMetric({
          namespace: process.env.METRICS_NAMESPACE || "ObservabilityPlatform",
          metricName: "EventRejected",
          service: "processor",
        });
        continue;
      }

      const { eventId, eventType } = body;

      // Transient failure
      if (body.failTransient) {
        throw new Error("Transient processing error");
      }

      try {
        const expiresAt = Math.floor(Date.now() / 1000) + 28 * 60 * 60;

        await dynamoDb.send(
          new PutCommand({
            TableName: TABLE_NAME,
            Item: {
              eventId,
              expiresAt,
            },
            ConditionExpression: "attribute_not_exists(eventId)",
          }),
        );
      } catch (err) {
        if (err.name === "ConditionalCheckFailedException") {
          console.log(
            JSON.stringify({
              level: "INFO",
              eventId,
              correlationId,
              message: "Idempotency: Duplicated Message ignored",
            }),
          );
          emitMetric({
            namespace: process.env.METRICS_NAMESPACE || "ObservabilityPlatform",
            metricName: "EventDuplicated",
            service: "processor",
          });
          continue;
        }
        throw err;
      }

      emitMetric({
        namespace: process.env.METRICS_NAMESPACE || "ObservabilityPlatform",
        metricName: "EventProcessed",
        service: "processor",
      });

      console.log(
        JSON.stringify({
          level: "INFO",
          eventId,
          correlationId,
          eventType,
          body,
          message: "Processed successfully",
        }),
      );
    } catch (err) {
      console.error(
        JSON.stringify({
          level: "ERROR",
          messageId,
          correlationId,
          body,
          error: err.message,
        }),
      );

      emitMetric({
        namespace: process.env.METRICS_NAMESPACE || "ObservabilityPlatform",
        metricName: "EventRetried",
        service: "processor",
      });

      failures.push({
        itemIdentifier: messageId,
      });
    }
  }

  return {
    batchItemFailures: failures,
  };
};
