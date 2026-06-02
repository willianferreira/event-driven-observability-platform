const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");
const { emitMetric } = require("../../shared/metrics");
const { randomUUID } = require("crypto");

const REQUIRED_FIELDS = ["eventId", "eventName", "eventType", "payload"];
const REQUIRED_PAYLOAD_FIELDS = [
  "order_id",
  "customer_id",
  "amount",
  "currency",
];

function validate(body) {
  const missing = [];

  for (const field of REQUIRED_FIELDS) {
    if (body[field] == null) missing.push(field);
  }

  if (body.payload != null) {
    for (const field of REQUIRED_PAYLOAD_FIELDS) {
      if (body.payload[field] == null) missing.push(`payload.${field}`);
    }
  }

  return missing;
}

const sqsClient = new SQSClient({
  region: process.env.AWS_REGION || "us-east-2",
});

exports.handler = async (event, context) => {
  const correlationId =
    event.headers?.["x-correlation-id"] ||
    event.headers?.["X-Correlation-ID"] ||
    randomUUID();

  try {
    const body = JSON.parse(event.body);

    const missingFields = validate(body);
    if (missingFields.length > 0) {
      console.warn(
        JSON.stringify({
          level: "WARN",
          correlationId,
          awsRequestId: context.awsRequestId,
          reason: "SchemaViolation",
          missingFields,
        }),
      );
      emitMetric({
        namespace: process.env.METRICS_NAMESPACE || "ObservabilityPlatform",
        metricName: "EventRejected",
        service: "ingestion",
      });
      return {
        statusCode: 400,
        headers: { "x-correlation-id": correlationId },
        body: JSON.stringify({
          message: "Contract violation",
          missingFields,
          correlationId,
        }),
      };
    }

    const normalizedEvent = {
      eventId: body.eventId,
      eventName: body.eventName,
      eventType: body.eventType,
      payload: body.payload,
      failTransient: body.failTransient === true,
      _metadata: {
        correlationId,
        awsRequestId: context.awsRequestId,
        receivedAt: new Date().toISOString(),
        sourceIp: event.requestContext?.http?.sourceIp ?? null,
        userAgent: event.headers?.["user-agent"] ?? null,
      },
    };

    await sqsClient.send(
      new SendMessageCommand({
        QueueUrl: process.env.SQS_QUEUE_URL,
        MessageBody: JSON.stringify(normalizedEvent),
      }),
    );

    console.log(
      JSON.stringify({
        level: "INFO",
        correlationId,
        awsRequestId: context.awsRequestId,
        eventId: body.eventId,
        eventType: body.eventType,
        message: "Event ingested successfully",
      }),
    );

    emitMetric({
      namespace: process.env.METRICS_NAMESPACE || "ObservabilityPlatform",
      metricName: "EventIngested",
      service: "ingestion",
    });

    return {
      statusCode: 200,
      headers: { "x-correlation-id": correlationId },
      body: JSON.stringify({
        message: "Event received and queued for processing",
        correlationId,
        eventId: body.eventId,
      }),
    };
  } catch (error) {
    console.error(
      JSON.stringify({
        level: "ERROR",
        correlationId,
        awsRequestId: context.awsRequestId,
        error: error.message,
      }),
    );
    emitMetric({
      namespace: process.env.METRICS_NAMESPACE || "ObservabilityPlatform",
      metricName: "EventFailed",
      service: "ingestion",
    });
    return {
      statusCode: 500,
      headers: { "x-correlation-id": correlationId },
      body: JSON.stringify({ message: "Internal Server Error", correlationId }),
    };
  }
};
