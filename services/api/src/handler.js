const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.IDEMPOTENCY_TABLE_NAME;

exports.handler = async (event) => {
  const failures = [];

  for (const record of event.Records) {
    const messageId = record.messageId;

    try {
      const body = JSON.parse(record.body);

      if (!body.eventId) {
        console.log(
          JSON.stringify({
            level: "WARN",
            messageId,
            reason: "Missing required field: eventId",
          }),
        );
        continue;
      }

      // Transient failure
      if (body.failTransient) {
        throw new Error("Transient processing error");
      }

      const eventId = body.eventId;

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
              message: "Duplicated message ignored",
            }),
          );
          continue;
        }
        throw err;
      }

      // Permanent error
      if (!body.type) {
        console.log(
          JSON.stringify({
            level: "WARN",
            eventId,
            reason: "Missing required field: type",
          }),
        );
        continue;
      }

      console.log(
        JSON.stringify({
          level: "INFO",
          eventId,
          message: "Processed successfully",
        }),
      );
    } catch (err) {
      console.log(
        JSON.stringify({
          level: "ERROR",
          messageId,
          error: err.message,
        }),
      );

      failures.push({
        itemIdentifier: messageId,
      });
    }
  }

  return {
    batchItemFailures: failures,
  };
};
