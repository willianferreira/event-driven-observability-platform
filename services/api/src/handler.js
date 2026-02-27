exports.handler = async (event) => {
  console.log(
    JSON.stringify({
      level: "INFO",
      message: "Event received",
      CountRecords: event.Records?.length || 0,
    }),
  );

  return {};
};
