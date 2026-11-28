import assert from "node:assert/strict";
import test from "node:test";

import { redactSensitive } from "../src/app-server-client.js";
import { formatMenuTitle, normalizeUsage } from "../src/usage-format.js";

test("normalizes Codex 5-hour and weekly windows", () => {
  const usage = normalizeUsage({
    rateLimitsByLimitId: {
      codex: {
        limitId: "codex",
        planType: "plus",
        primary: {
          usedPercent: 34,
          windowDurationMins: 300,
          resetsAt: 1780000000,
        },
        secondary: {
          usedPercent: 37,
          windowDurationMins: 10080,
          resetsAt: 1780500000,
        },
      },
    },
  });

  assert.equal(usage.limitId, "codex");
  assert.equal(usage.planType, "plus");
  assert.equal(usage.fiveHour.remainingPercent, 66);
  assert.equal(usage.weekly.remainingPercent, 63);
  assert.equal(formatMenuTitle(usage), "Codex 5h 66% 7d 63%");
});

test("falls back to backward-compatible single snapshot", () => {
  const usage = normalizeUsage({
    rateLimits: {
      limitId: "codex",
      primary: {
        usedPercent: 0,
        windowDurationMins: 300,
      },
      secondary: {
        usedPercent: 101,
        windowDurationMins: 10080,
      },
    },
  });

  assert.equal(usage.fiveHour.remainingPercent, 100);
  assert.equal(usage.weekly.remainingPercent, 0);
});

test("redacts sensitive app-server stderr snippets", () => {
  const redacted = redactSensitive(
    [
      "token: sk-local-development-secret",
      "Authorization = Bearer should-not-survive",
      "api_key=also-should-not-survive",
      "aaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbb.cccccccccccccccccccc",
    ].join("\n"),
  );

  assert.match(redacted, /token: \[redacted\]/);
  assert.match(redacted, /Authorization = \[redacted\]/);
  assert.match(redacted, /api_key=\[redacted\]/);
  assert.match(redacted, /\[redacted-jwt\]/);
  assert.doesNotMatch(redacted, /should-not-survive|also-should-not-survive/);
});

test("keeps incomplete and legacy Codex windows in their own slots", () => {
  const format = (primary, secondary) => formatMenuTitle(normalizeUsage({ rateLimits: { primary, secondary } }));
  assert.equal(format(null, { windowDurationMins: 10080, usedPercent: 23 }), "Codex 5h -- 7d 77%");
  assert.equal(format({ windowDurationMins: 300 }, { usedPercent: 0 }), "Codex 5h -- 7d 100%");
  assert.equal(format({ usedPercent: 100 }, { usedPercent: 0 }), "Codex 5h 0% 7d 100%");
  assert.equal(format({ windowDurationMins: 10080, usedPercent: 100 }, { windowDurationMins: 300, usedPercent: 0 }), "Codex 5h 100% 7d 0%");
  assert.equal(format({ windowDurationMins: 1440, usedPercent: 50 }, null), "Codex 5h -- 7d --");
});

test("rounds remaining quota after subtraction, like the macOS app", () => {
  for (const [usedPercent, remainingPercent] of [[0.5, 100], [22.5, 78], [99.5, 1], [100, 0], [0, 100]]) {
    const usage = normalizeUsage({ rateLimits: { primary: { usedPercent } } });
    assert.equal(usage.fiveHour.remainingPercent, remainingPercent);
    assert.equal(usage.fiveHour.usedPercent + remainingPercent, 100);
  }
});

test("Codex accepts its own windows or an unlabelled legacy response", () => {
  const windows = { secondary: { usedPercent: 23, windowDurationMins: 10080 } };
  const other = { ...windows, limitId: "other" };
  for (const data of [{ rateLimitsByLimitId: { other } }, { rateLimits: other },
                      { rateLimitsByLimitId: { codex: other } },
                      { rateLimitsByLimitId: { other }, rateLimits: windows }]) {
    assert.equal(formatMenuTitle(normalizeUsage(data)), "Codex 5h -- 7d --");
  }
  assert.equal(normalizeUsage({ rateLimits: windows }).weekly.remainingPercent, 77);
  assert.equal(normalizeUsage({ rateLimitsByLimitId: { other, codex: windows } }).weekly.remainingPercent, 77);
});
