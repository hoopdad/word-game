const DEFAULT_STOP_WORDS = new Set([
  'a', 'about', 'above', 'after', 'again', 'against', 'all', 'also', 'am', 'an', 'and', 'any', 'are',
  'as', 'at', 'be', 'because', 'been', 'before', 'being', 'below', 'between', 'both', 'but', 'by',
  'can', 'content', 'data', 'did', 'do', 'does', 'doing', 'down', 'during', 'each', 'few', 'for',
  'from', 'further', 'had', 'has', 'have', 'having', 'he', 'her', 'here', 'hers', 'herself', 'him',
  'himself', 'his', 'how', 'i', 'if', 'in', 'info', 'information', 'into', 'is', 'it', 'its', 'itself',
  'just', 'me', 'more', 'most', 'my', 'myself', 'no', 'nor', 'not', 'of', 'off', 'on', 'once', 'only',
  'or', 'other', 'our', 'ours', 'ourselves', 'out', 'over', 'own', 'page', 'same', 'section', 'she',
  'should', 'so', 'some', 'such', 'than', 'that', 'the', 'their', 'theirs', 'them', 'themselves',
  'then', 'there', 'these', 'they', 'this', 'those', 'through', 'to', 'too', 'under', 'up', 'use',
  'used', 'using', 'very', 'was', 'we', 'were', 'what', 'when', 'where', 'which', 'while', 'who',
  'why', 'will', 'with', 'you', 'your', 'yours', 'yourself', 'yourselves'
]);

function stripHtml(text) {
  return String(text || '')
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&amp;/gi, ' and ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractWords(text) {
  const sanitized = stripHtml(text).toLowerCase();
  const words = sanitized.match(/[a-z][a-z0-9'-]{1,}/g);
  return words || [];
}

function extractPhrases(words, sizes = [2, 3]) {
  const phrases = [];

  for (const size of sizes) {
    for (let index = 0; index <= words.length - size; index += 1) {
      const slice = words.slice(index, index + size);
      const nonStopTokens = slice.filter((token) => !DEFAULT_STOP_WORDS.has(token));
      if (nonStopTokens.length === 0) {
        continue;
      }

      const hasDomainHint = nonStopTokens.some((token) => token.length >= 4);
      if (!hasDomainHint && nonStopTokens.length < 2) {
        continue;
      }

      phrases.push(slice.join(' '));
    }
  }

  return phrases;
}

function countItems(items) {
  const counts = new Map();
  for (const item of items) {
    counts.set(item, (counts.get(item) || 0) + 1);
  }
  return counts;
}

function scoreEntries(entries) {
  return entries.sort((left, right) => {
    if (right.score !== left.score) {
      return right.score - left.score;
    }
    return left.term.localeCompare(right.term);
  });
}

function selectKeywords(wordCounts) {
  const entries = [];

  for (const [word, count] of wordCounts.entries()) {
    if (DEFAULT_STOP_WORDS.has(word)) {
      continue;
    }
    if (count < 2 && word.length < 7) {
      continue;
    }
    entries.push({
      term: word,
      score: count * 10 + Math.min(word.length, 10)
    });
  }

  return scoreEntries(entries).slice(0, 15).map((entry) => entry.term);
}

function selectPhrases(phraseCounts) {
  const entries = [];

  for (const [phrase, count] of phraseCounts.entries()) {
    const tokens = phrase.split(' ');
    const nonStopCount = tokens.filter((token) => !DEFAULT_STOP_WORDS.has(token)).length;
    const hasLongToken = tokens.some((token) => token.length >= 8);

    if (nonStopCount === 0) {
      continue;
    }
    if (count < 2 && !hasLongToken && nonStopCount < 2) {
      continue;
    }

    entries.push({
      term: phrase,
      score: count * 10 + Math.min(phrase.length, 20)
    });
  }

  return scoreEntries(entries).slice(0, 15).map((entry) => entry.term);
}

function groupCategories(content) {
  const words = extractWords(content);
  const phrases = extractPhrases(words);
  const keywords = selectKeywords(countItems(words));
  const keyPhrases = selectPhrases(countItems(phrases));

  const categories = [];
  if (keyPhrases.length > 0) {
    categories.push({ name: 'key_phrases', terms: keyPhrases });
  }
  if (keywords.length > 0) {
    categories.push({ name: 'keywords', terms: keywords });
  }

  return {
    categories,
    candidateStats: {
      wordsExamined: words.length,
      keywordCount: keywords.length,
      phraseCount: keyPhrases.length
    }
  };
}

module.exports = {
  DEFAULT_STOP_WORDS,
  extractWords,
  extractPhrases,
  groupCategories
};
