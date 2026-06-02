function createLogger(baseContext = {}) {
  function write(level, fields) {
    console.log(
      JSON.stringify({
        level,
        timestamp: new Date().toISOString(),
        ...baseContext,
        ...fields,
      }),
    );
  }

  return {
    info: (fields) => write("INFO", fields),
    warn: (fields) => write("WARN", fields),
    error: (fields) => write("ERROR", fields),
  };
}

module.exports = { createLogger };
