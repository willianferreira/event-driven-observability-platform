const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

const sqsClient = new SQSClient({
  region: process.env.AWS_REGION || "us-east-2",
});

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body);

    if (!body.eventId) {
      return {
        statusCode: 400,
        body: JSON.stringify({ message: "eventId is required" }),
      };
    }

    const params = {
      QueueUrl: process.env.SQS_QUEUE_URL,
      MessageBody: JSON.stringify(body),
    };

    await sqsClient.send(new SendMessageCommand(params));

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Event received and queued for processing",
      }),
    };
  } catch (error) {
    return {
      statusCode: 400,
      body: JSON.stringify({ message: "Invalid Payload" }),
    };
  }
};
