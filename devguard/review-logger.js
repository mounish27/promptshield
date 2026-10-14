#!/usr/bin/env node
/**
 * PromptShield Review Logger
 * Reads a review report file and sends it to the gateway for dashboard visibility.
 * Also maintains a local review log at ~/.devguard/reviews.jsonl
 *
 * Usage:
 *   node review-logger.js --type review --report .promptshield/review-20260519-143022.md
 *   node review-logger.js --type session-end   (called by post-tool hook)
 */

const fs    = require("fs");
const path  = require("path");
const os    = require("os");
const http  = require("http");
const https = require("https");

const CONFIG      = path.join(os.homedir(), ".devguard", "config", "config.json");
const REVIEW_LOG  = path.join(os.homedir(), ".devguard", "reviews.jsonl");
const PS_DIR = path.join(process.cwd(), ".promptshield");
const LOCAL_STORE = path.join(PS_DIR, "reviews");

function cfg() {
  try { return JSON.parse(fs.readFileSync(CONFIG, "utf8")); }
  catch { return {}; }
}

function readStdin() {
  return new Promise(r => {
    if (process.stdin.isTTY) { r(null); return; }
    let d = "";
    process.stdin.setEncoding("utf8").on("data", c => d += c).on("end", () => {
      try { r(JSON.parse(d)); } catch { r({ raw: d }); }
    });
    setTimeout(() => r(null), 1000);
  });
}

// ── Parse CLI args ────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const typeIdx   = args.indexOf("--type");
const reportIdx = args.indexOf("--report");
const reviewType   = typeIdx   >= 0 ? args[typeIdx + 1]   : "review";
const reportFile   = reportIdx >= 0 ? args[reportIdx + 1] : null;

// ── Parse review report for structured data ────────────────────────────────
function parseReport(content) {
  const lines = content.split("\n");
  const result = {
    verdict: "PASS",
    filesReviewed: 0,
    blocking: 0,
    warnings: 0,
    deliberationStatus: "UNKNOWN",
    securityStatus: "PASS",
    testStatus: "UNKNOWN",
    qualityStatus: "PASS",
    summary: "",
  };

  for (const line of lines) {
    if (/verdict:\s*(PASS|WARN|BLOCK)/i.test(line)) result.verdict = line.match(/PASS|WARN|BLOCK/i)[0].toUpperCase();
    if (/files reviewed:\s*(\d+)/i.test(line)) result.filesReviewed = parseInt(line.match(/\d+/)[0]);
    if (/(\d+) blocking/i.test(line)) result.blocking = parseInt(line.match(/\d+/)[0]);
    if (/(\d+) warning/i.test(line)) result.warnings = parseInt(line.match(/\d+/)[0]);
    if (/deliberation.*:(ALIGNED|DEVIATION|CONTRADICTION)/i.test(line)) result.deliberationStatus = line.match(/ALIGNED|DEVIATION|CONTRADICTION/i)[0].toUpperCase();
    if (/security.*:(PASS|WARN|BLOCK)/i.test(line)) result.securityStatus = line.match(/PASS|WARN|BLOCK/i)[0].toUpperCase();
    if (/test coverage.*:(COMPLETE|PARTIAL|MISSING)/i.test(line)) result.testStatus = line.match(/COMPLETE|PARTIAL|MISSING/i)[0].toUpperCase();
    if (/code quality.*:(PASS|WARN|FAIL)/i.test(line)) result.qualityStatus = line.match(/PASS|WARN|FAIL/i)[0].toUpperCase();
  }

  // Extract first paragraph after ## Summary as the summary
  const summaryMatch = content.match(/## Summary\n([\s\S]*?)(?=\n##|$)/);
  if (summaryMatch) result.summary = summaryMatch[1].trim().slice(0, 500);

  return result;
}

// ── Send to gateway ───────────────────────────────────────────────────────────
function sendToGateway(gatewayUrl, token, payload) {
  return new Promise(resolve => {
    const isHttps = gatewayUrl.startsWith("https");
    const lib = isHttps ? https : http;
    const body = JSON.stringify(payload);
    const u = new URL("/api/v1/reviews", gatewayUrl);
    const req = lib.request({
      hostname: u.hostname,
      port: u.port || (isHttps ? 443 : 80),
      path: u.pathname,
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body),
        "authorization": `Bearer ${token}`,
      }
    }, res => {
      res.on("data", () => {});
      res.on("end", () => resolve(res.statusCode < 300));
    });
    req.on("error", () => resolve(false));
    req.setTimeout(4000, () => { req.destroy(); resolve(false); });
    req.write(body);
    req.end();
  });
}

// ── Save locally ──────────────────────────────────────────────────────────────
function saveLocally(entry) {
  try {
    fs.appendFileSync(REVIEW_LOG, JSON.stringify(entry) + "\n");
  } catch { /* silent */ }
}

// ── Main ───────────────────────────────────────────────────────────────────────
async function main() {
  const c = cfg();
  const ts = new Date().toISOString();

  let reportContent = null;
  let parsed = {};

  // Read report file
  if (reportFile && fs.existsSync(reportFile)) {
    reportContent = fs.readFileSync(reportFile, "utf8");
    parsed = parseReport(reportContent);
  }

  // Also check stdin (piped report)
  const stdin = await readStdin();
  if (stdin?.report) {
    reportContent = stdin.report;
    parsed = parseReport(reportContent);
  }

  const entry = {
    ts,
    developer: c.developerName || "unknown",
    deviceName: c.developerName || os.hostname(),
    type: reviewType,
    verdict: parsed.verdict || "UNKNOWN",
    filesReviewed: parsed.filesReviewed || 0,
    blocking: parsed.blocking || 0,
    warnings: parsed.warnings || 0,
    deliberationStatus: parsed.deliberationStatus || "UNKNOWN",
    securityStatus: parsed.securityStatus || "PASS",
    testStatus: parsed.testStatus || "UNKNOWN",
    qualityStatus: parsed.qualityStatus || "PASS",
    summary: parsed.summary || "",
    reportFile: reportFile || null,
    cwd: process.cwd(),
  };

  // Always save locally
  saveLocally(entry);

  // Send to gateway (non-blocking — never fail the developer)
  if (c.gatewayUrl && c.developerToken) {
    await sendToGateway(c.gatewayUrl, c.developerToken, entry);
  }

  // Print confirmation
  const verdict = entry.verdict;
  const icon = verdict === "PASS" ? "✓" : verdict === "BLOCK" ? "✕" : "⚠";
  const color = verdict === "PASS" ? "\x1b[32m" : verdict === "BLOCK" ? "\x1b[31m" : "\x1b[33m";
  process.stderr.write(
    `\n${color}${icon} Review logged: ${verdict} — ${entry.blocking} blocking · ${entry.warnings} warnings\x1b[0m\n` +
    (reportFile ? `  Report: ${reportFile}\n` : "") +
    `  Saved:  ${REVIEW_LOG}\n\n`
  );

  process.exit(0);
}

main().catch(() => process.exit(0));
