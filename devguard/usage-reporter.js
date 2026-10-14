#!/usr/bin/env node
// PromptShield PostToolUse / UserPromptSubmit Hook — reports token usage to gateway
const fs = require("fs"), path = require("path"), os = require("os"), https = require("https");
const CONFIG = path.join(os.homedir(), ".devguard", "config", "config.json");
const QUEUE  = path.join(os.homedir(), ".devguard", "queue.jsonl");
const cfg = () => { try { return JSON.parse(fs.readFileSync(CONFIG, "utf8")); } catch { return {}; } };
const readStdin = () => new Promise(r => { let d=""; process.stdin.setEncoding("utf8").on("data",c=>d+=c).on("end",()=>{try{r(JSON.parse(d))}catch{r(null)}}); setTimeout(()=>r(null),2000); });

function send(url, token, body) {
  return new Promise(r => {
    const u = new URL(url), data = JSON.stringify(body);
    const isHttps = u.protocol === "https:";
    const lib = isHttps ? require("https") : require("http");
    const req = lib.request({
      hostname:u.hostname, port:u.port||(isHttps?443:80), path:u.pathname, method:"POST",
      headers:{"Content-Type":"application/json","Content-Length":Buffer.byteLength(data),"Authorization":`Bearer ${token}`}
    }, res => r(res.statusCode < 300));
    req.on("error",()=>r(false));
    req.setTimeout(3000,()=>{req.destroy();r(false)});
    req.write(data); req.end();
  });
}

function tokensFromToolCall(ctx) {
  const usage = ctx?.usage || ctx?.response?.usage || {};
  const inputChars = JSON.stringify(ctx?.tool_input || {}).length;
  const outputChars = String(ctx?.tool_response || "").length;
  const estimatedInput = Math.ceil(inputChars / 4);
  const estimatedOutput = Math.ceil(outputChars / 4);
  const inp = usage.input_tokens || estimatedInput;
  const out = usage.output_tokens || estimatedOutput;
  const tokenSource = usage.input_tokens ? "exact" : "estimated";
  return { inp, out, tokenSource };
}

function tokensFromUserPrompt(ctx) {
  const usage = ctx?.usage || ctx?.response?.usage || {};
  const promptChars = String(ctx?.prompt || ctx?.message || "").length;
  const estimatedPromptTokens = Math.ceil(promptChars / 4);
  const inp = usage.input_tokens || estimatedPromptTokens;
  const out = usage.output_tokens || 0;
  const tokenSource = usage.input_tokens ? "exact" : "estimated";
  return { inp, out, tokenSource };
}

function resolveTokens(ctx) {
  const event = ctx?.hook_event_name || "";
  if (event === "UserPromptSubmit") {
    return tokensFromUserPrompt(ctx);
  }
  return tokensFromToolCall(ctx);
}

(async () => {
  const c = cfg();
  if (!c.developerToken || !c.gatewayUrl) return;
  const ctx = await readStdin();
  if (!ctx) return;

  const { inp, out, tokenSource } = resolveTokens(ctx);
  if (inp + out === 0) return;

  const event = {
    ts: new Date().toISOString(),
    developer: c.developerName,
    token: c.developerToken,
    tool: ctx?.tool_name || (ctx?.hook_event_name === "UserPromptSubmit" ? "prompt" : "chat"),
    inputTokens: inp,
    outputTokens: out,
    totalTokens: inp + out,
    costUsd: inp * 0.000003 + out * 0.000015,
    model: ctx?.model || ctx?.response?.model || "claude-sonnet-4-6",
    devguardVerdict: ctx?.devguard_verdict || "PASS",
    register: true,
    tokenSource,
  };
  const ok = await send(`${c.gatewayUrl}/api/v1/usage`, c.developerToken, event);
  if (!ok) { try { fs.appendFileSync(QUEUE, JSON.stringify(event)+"\n"); } catch {} }
})().catch(()=>{});
