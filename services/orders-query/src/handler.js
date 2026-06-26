const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand } = require("@aws-sdk/lib-dynamodb");
const { createLogger } = require("../../shared/logger");

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client);

const ORDERS_TABLE_NAME = process.env.ORDERS_TABLE_NAME;

exports.handler = async (event, context) => {
  const eventId = event.pathParameters?.eventId;
  const correlationId =
    event.headers?.["x-correlation-id"] ||
    event.headers?.["X-Correlation-ID"] ||
    context.awsRequestId;

  const log = createLogger({
    service: "orders-query",
    correlationId,
    awsRequestId: context.awsRequestId,
  });

  if (!eventId) {
    log.warn({ reason: "MissingPathParameter", parameter: "eventId" });
    return {
      statusCode: 400,
      headers: { "x-correlation-id": correlationId },
      body: JSON.stringify({ message: "eventId path parameter is required" }),
    };
  }

  try {
    const result = await dynamoDb.send(
      new GetCommand({
        TableName: ORDERS_TABLE_NAME,
        Key: { eventId },
      }),
    );

    if (!result.Item) {
      log.info({ eventId, message: "Order not found" });
      return {
        statusCode: 404,
        headers: { "x-correlation-id": correlationId },
        body: JSON.stringify({ message: "Order not found" }),
      };
    }

    log.info({ eventId, message: "Order found" });
    return {
      statusCode: 200,
      headers: { "x-correlation-id": correlationId },
      body: JSON.stringify(result.Item),
    };
  } catch (error) {
    log.error({ eventId, error: error.message });
    return {
      statusCode: 500,
      headers: { "x-correlation-id": correlationId },
      body: JSON.stringify({ message: "Internal Server Error" }),
    };
  }
};
