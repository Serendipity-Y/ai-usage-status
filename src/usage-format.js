const FIVE_HOURS_MINS = 5 * 60;
const WEEK_MINS = 7 * 24 * 60;

export function normalizeUsage(rateLimitResponse, now = new Date()) {
  const byID = rateLimitResponse?.rateLimitsByLimitId ?? {};
  const keyed = byID.codex;
  const legacy = rateLimitResponse?.rateLimits;
  const hasIDs = Object.keys(byID).length > 0;
  const keyedMatches = keyed && (keyed.limitId == null || keyed.limitId === "codex");
  const legacyMatches = legacy && (legacy.limitId === "codex" || (legacy.limitId == null && !hasIDs));
  const snapshot = (keyedMatches && keyed) || (legacyMatches && legacy);

  if (!snapshot) {
    if (hasIDs || legacy) {
      return { limitId: "codex", planType: null, fiveHour: null, weekly: null, windows: [] };
    }
    throw new Error("Codex rate-limit response did not include a usable snapshot.");
  }

  const [primary, secondary] = [snapshot.primary, snapshot.secondary]
    .map(window => window ? normalizeWindow(window, now) : null);
  const windows = [primary, secondary].filter(Boolean);

  function resolve(minutes, legacy) {
    return windows.find(window => approximately(window.windowDurationMins, minutes))
      ?? (legacy?.windowDurationMins == null ? legacy : null);
  }

  return {
    limitId: snapshot.limitId ?? "codex",
    planType: snapshot.planType ?? null,
    fiveHour: resolve(FIVE_HOURS_MINS, primary),
    weekly: resolve(WEEK_MINS, secondary),
    windows,
  };
}

function percentText(window) {
  return window?.remainingPercent == null ? "--" : String(window.remainingPercent) + "%";
}

export function formatMenuTitle(usage) {
  return "Codex 5h " + percentText(usage.fiveHour) + " 7d " + percentText(usage.weekly);
}

export function formatTextStatus(usage) {
  return [
    formatMenuTitle(usage),
    "5-hour remaining: " + percentText(usage.fiveHour),
    "5-hour reset: " + formatReset(usage.fiveHour?.resetsAt),
    "Weekly remaining: " + percentText(usage.weekly),
    "Weekly reset: " + formatReset(usage.weekly?.resetsAt),
  ].join("\n");
}

function normalizeWindow(window, now) {
  const rawUsed = toNumber(window.usedPercent);
  const remainingPercent = rawUsed === null ? null : clampPercent(100 - rawUsed);
  const usedPercent = remainingPercent === null ? null : 100 - remainingPercent;
  const resetsAt = typeof window.resetsAt === "number" ? new Date(window.resetsAt * 1000) : null;
  return {
    usedPercent,
    remainingPercent,
    windowDurationMins: toNumber(window.windowDurationMins),
    resetsAt,
    staleAt: new Date(now.getTime()),
  };
}

function toNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function clampPercent(value) {
  if (value === null) {
    return null;
  }
  return Math.max(0, Math.min(100, Math.round(value)));
}

function approximately(value, target) {
  return typeof value === "number" && Math.abs(value - target) <= 1;
}

function formatReset(date) {
  if (!date) {
    return "unknown";
  }
  return date.toLocaleString(undefined, { hour12: false });
}
