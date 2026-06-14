async function mapWithConcurrency(items, concurrency, mapper) {
  if (!Array.isArray(items)) {
    throw new TypeError('items must be an array');
  }
  if (typeof mapper !== 'function') {
    throw new TypeError('mapper must be a function');
  }

  const limit = Number.isInteger(concurrency) && concurrency > 0 ? concurrency : 1;
  const results = new Array(items.length);
  let nextIndex = 0;

  async function worker() {
    while (true) {
      const currentIndex = nextIndex;
      if (currentIndex >= items.length) {
        return;
      }
      nextIndex += 1;
      results[currentIndex] = await mapper(items[currentIndex], currentIndex);
    }
  }

  const workerCount = Math.min(limit, items.length);
  const workers = [];
  for (let index = 0; index < workerCount; index += 1) {
    workers.push(worker());
  }

  await Promise.all(workers);
  return results;
}

module.exports = {
  mapWithConcurrency
};
