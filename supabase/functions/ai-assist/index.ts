// @ts-nocheck
// Site Specific Safety File Generator – AI assistant (Supabase Edge Function "ai-assist")
//
// The app calls this function; this function calls Claude through the Anthropic API.
// The Anthropic key never reaches the browser. Every request is checked against the
// database first (signed in, active, daily limit) and recorded in the activity log.
//
// Secrets (Supabase > Edge Functions > Secrets):
//   ANTHROPIC_API_KEY  required
//   ANTHROPIC_MODEL    optional, defaults to claude-sonnet-5-5

const SB_URL = Deno.env.get("SUPABASE_URL") || "";
const KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const MODEL = Deno.env.get("ANTHROPIC_MODEL") || "claude-sonnet-5-5";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

const SYSTEM =
  "You are an experienced South African occupational health and safety (OHS) practitioner helping GSRC Management " +
  "prepare site-specific safety files. Work to the Occupational Health and Safety Act 85 of 1993, its regulations " +
  "(including the Construction Regulations 2014) and the client's own requirements. Write in plain South African English, " +
  "in short clear sentences. Never invent regulation or section numbers: if you are not certain of a reference, write " +
  "[confirm reference]. Text in square brackets such as [name] or [ID number] replaces personal information; keep it as it is. " +
  "Do not include any personal information. Write as the company itself: never mention AI, artificial intelligence, a language model, an assistant or that the text was generated or drafted automatically. Reply with exactly the format asked for and nothing else.";

function clip(v, n) {
  return String(v == null ? "" : v).slice(0, n);
}

function contextBlock(b) {
  const docs = Array.isArray(b.documents) ? b.documents.slice(0, 400) : [];
  const reqs = Array.isArray(b.requirements) ? b.requirements.slice(0, 400) : [];
  return clip(
    "COMPANY (principal contractor): " + clip(b.company, 200) + "\n" +
    "SITE: " + clip(b.site, 200) + "\nCLIENT: " + clip(b.client, 200) + "\n" +
    "SCOPE OF WORK: " + clip(b.scope, 4000) + "\n" +
    "TYPES OF WORK: " + clip((b.work_types || []).join("; "), 2000) + "\n" +
    "TASKS AND ACTIVITIES: " + clip((b.tasks || []).join("; "), 2000) + "\n" +
    "CONTRACTOR USED: " + (b.contractor ? "yes" : "no") + "\n\n" +
    "CLIENT REQUIREMENTS (from the client's specification or safety file index):\n" +
    reqs.map((r) =>
      clip(r.no, 20) + ". " + clip(r.text, 1500) +
      (Array.isArray(r.subs) ? r.subs.slice(0, 50).map((s) => "\n   " + clip(s.no, 20) + " " + clip(s.text, 1000)).join("") : "")
    ).join("\n") +
    "\n\nDOCUMENTS IN THIS SAFETY FILE (title | document number):\n" +
    docs.map((d) => clip(d[0], 200) + " | " + clip(d[1], 80)).join("\n"),
    150000,
  );
}

function buildTask(b) {
  const task = String(b.task || "");
  if (task === "read_spec") {
    const content = [];
    const file = b.file;
    if (file && file.data) {
      if (String(file.data).length > 14_000_000) throw new Error("The file is too large. Use a file under 10 MB.");
      if (file.type === "application/pdf") {
        content.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: file.data } });
      } else if (/^image\/(png|jpeg|gif|webp)$/.test(file.type)) {
        content.push({ type: "image", source: { type: "base64", media_type: file.type, data: file.data } });
      } else throw new Error("Unsupported file type.");
    }
    if (b.text) content.push({ type: "text", text: "DOCUMENT TEXT:\n" + clip(b.text, 150000) });
    if (!content.length) throw new Error("No document was sent.");
    content.push({
      type: "text",
      text:
        "This is a client's health and safety specification or safety file index. List every requirement the contractor " +
        "must meet and every document or record it must provide, in the client's own order and numbering.\n" +
        "Reply in plain text only:\n" +
        "- First line: the document's title.\n" +
        "- Then one requirement per line, starting with its number exactly as the client numbers it, for example '1. ...' or '4.2 ...'.\n" +
        "- If the client does not number items, number them yourself 1, 2, 3 in order.\n" +
        "- Sub-points without their own number start with '- ' on their own line under their parent.\n" +
        "- Keep the client's wording. Shorten only lines longer than 40 words, keeping the meaning.\n" +
        "- Leave out cover pages, contents pages, definitions and general background that place no requirement on the contractor.\n" +
        "No commentary before or after the list.",
    });
    return { content, max: 8000 };
  }
  if (task === "annex") {
    return {
      max: 16000,
      content: [{
        type: "text",
        text: contextBlock(b) + "\n\n" +
          "Write the SHE plan annexure that responds to the client's requirements. For each requirement and sub-requirement, " +
          "state what the company will do on site to meet it, in 2 to 5 sentences, using the company's name. Refer to the documents " +
          "in the list by title and document number where they meet the requirement. Where evidence must be supplied before work " +
          "starts, say who supplies what. If no document in the list covers a requirement, say what will be done and end with " +
          "'[Document to be developed]'. Be specific to this scope of work; do not repeat the requirement back.\n" +
          "Reply with JSON only, in this form:\n" +
          '{"items":[{"no":"1","text":"..."},{"no":"25.a","text":"..."}]}\n' +
          "Use exactly the numbers given in the requirements list, including sub-item numbers such as 25.a.",
      }],
    };
  }
  if (task === "gap_check") {
    return {
      max: 6000,
      content: [{
        type: "text",
        text: contextBlock(b) + "\n\n" +
          "Check each client requirement against the documents in this safety file. For each one decide: 'covered' (a document " +
          "clearly meets it), 'partial' (a document exists but probably does not cover everything asked) or 'missing' (nothing " +
          "meets it, or only external evidence can, such as a certificate the company must obtain). Give a one-sentence finding " +
          "and one concrete action.\n" +
          "Reply with JSON only, in this form:\n" +
          '{"items":[{"no":"1","status":"covered","finding":"...","action":"..."}]}',
      }],
    };
  }
  if (task === "analyse_scope") {
    // Done in two parts at the same time (what the job needs, and the job hazards) so that
    // a detailed scope neither runs out of reply space nor takes too long.
    const cat = b.catalog || {};
    const list = (x) => (Array.isArray(x) ? x.slice(0, 200).map((v) => "- " + clip(v, 120)).join("\n") : "");
    const base = [];
    const file = b.file;
    if (file && file.data) {
      if (String(file.data).length > 14_000_000) throw new Error("The file is too large. Use a file under 10 MB.");
      if (file.type === "application/pdf") base.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: file.data } });
      else if (/^image\/(png|jpeg|gif|webp)$/.test(file.type)) base.push({ type: "image", source: { type: "base64", media_type: file.type, data: file.data } });
      else throw new Error("Unsupported file type.");
    }
    if (b.doc_text) base.push({ type: "text", text: "SCOPE DOCUMENT TEXT:\n" + clip(b.doc_text, 120000) });
    const ctx = contextBlock({ ...b, documents: [] }) + "\n\n";
    const partA = base.concat([{
      type: "text",
      text: ctx +
        "CATALOGUE (choose only from these, using the names exactly as written):\n" +
        "WORK TYPES:\n" + list(cat.work_types) + "\n\nTASKS AND ACTIVITIES:\n" + list(cat.tasks) +
        "\n\nEQUIPMENT (each has an inspection register):\n" + list(cat.equipment) + "\n\nAPPOINTMENTS:\n" + list(cat.appointments) + "\n\n" +
        "Read the scope of work (and the scope document, if one is attached) and decide everything this job needs for its site-specific " +
        "safety file under the OHS Act and the Construction Regulations 2014: the work types, tasks and activities, equipment that will be " +
        "used on site, and the written appointments. Choose the closest catalogue entries even when the scope uses different words " +
        "(for example machinery inspection, overhaul or commissioning work). Be complete but do not add things the scope gives no reason for. " +
        "Keep each \"why\" under 15 words. List anything the preparer must confirm because the scope is unclear (at most 6 short items).\n" +
        "Reply with JSON only, in this form:\n" +
        '{"summary":"2-3 sentences","work_types":[{"name":"...","why":"..."}],"tasks":[{"name":"...","why":"..."}],' +
        '"equipment":[{"name":"...","why":"..."}],"appointments":[{"name":"...","why":"..."}],"contractor_likely":false,"confirm":["..."]}',
    }]);
    const partB = base.concat([{
      type: "text",
      text: ctx +
        "Read the scope of work (and the scope document, if one is attached). List up to 12 hazards specific to this job that a general " +
        "work-type hazard list would miss, each rated before controls with likelihood and severity from 1 to 5, with at most 4 short, " +
        "practical controls and the PPE. Keep every field short.\n" +
        "Reply with JSON only, in this form:\n" +
        '{"hazards":[{"activity":"...","hazard":"...","consequence":"...","likelihood":3,"severity":4,"controls":["..."],"ppe":"..."}]}',
    }]);
    return { parts: [partA, partB], max: 6000, merge: "*" };
  }
  if (task === "she_plan") {
    // Written in up to three parts at the same time, so the whole plan finishes well inside the time limit.
    const spec = b.mode === "spec";
    const extra = "\nTEAM ROLES ON SITE: " + clip((b.team_roles || []).join("; "), 2000) +
      "\nWRITTEN APPOINTMENTS IN THIS FILE: " + clip((b.appointments || []).join("; "), 3000);
    const HEAD = ["Scope and description of the work", "Legal and client requirements", "Organisation, responsibilities and appointments",
      "Risk assessment", "Safe work procedures and permits to work", "Fall protection (only if there is work at height)",
      "Plant, equipment and inspections", "Competence, training and medical fitness", "Induction and communication",
      "Personal protective equipment", "Emergency preparedness and first aid", "Incident reporting and investigation",
      "Contractor management (only if contractors are used)", "Occupational health and hygiene",
      "Environmental controls and housekeeping", "Monitoring, inspections and audits", "Health and safety file and records",
      "Review of this plan"];
    const reqs = Array.isArray(b.requirements) ? b.requirements : [];
    const groups = [];
    if (spec) {
      const n = Math.max(1, Math.min(3, Math.ceil(reqs.length / 6)));
      for (let g = 0; g < n; g++) groups.push(reqs.filter((_, k) => k % n === g));
    } else {
      groups.push(HEAD.slice(0, 6), HEAD.slice(6, 12), HEAD.slice(12));
    }
    const fmt = "\nWrite in plain South African English, using the company's name. Each section is 60 to 180 words: specific, " +
      "practical and not repeating other sections. Paragraphs are separated by new lines; list items start with '- '.\n" +
      "Reply with JSON only, in this form:\n" + '{"sections":[{"no":"1","heading":"...","text":"..."}]}';
    const parts = groups.map((grp, gi) => {
      if (spec) {
        return [{ type: "text", text: contextBlock(b) + extra + "\n\n" +
          "You are writing part of the site-specific SHE plan for this job under the client's own specification. Write sections ONLY for " +
          "these client requirements: " + grp.map((r) => clip(r.no, 20)).join(", ") + ". Use one section per requirement, with exactly the " +
          "client's number and a short heading taken from the requirement. In each section state what the company will do on site to meet " +
          "the requirement and its sub-items, specific to this scope of work, and refer to the documents in the file by title and number. " +
          "Where evidence must be supplied, say who supplies what and when. Where no document in the file covers a requirement, say what " +
          "will be done and end with '[Document to be developed]'." + fmt }];
      }
      const start = gi * 6 + 1;
      return [{ type: "text", text: contextBlock(b) + extra + "\n\n" +
        "You are writing part of the site-specific SHE plan for this job, as required by the Construction Regulations 2014 (the principal " +
        "contractor's health and safety plan) and the OHS Act. Write ONLY these sections, in this order, numbering them from " + start +
        ", and leave out any that do not apply to this scope: " + grp.join("; ") + ". Write each section specifically for this scope, " +
        "site and client, and refer to the documents in the file by title and number." + fmt }];
    });
    return { parts, max: 6000, merge: "sections" };
  }
  if (task === "improve_doc") {
    return {
      max: 6000,
      content: [{
        type: "text",
        text: contextBlock({ ...b, documents: [] }) + "\n\n" +
          "DOCUMENT TO REVIEW: " + clip(b.title, 200) + (/appointment/i.test(String(b.title)) ? "\n(This is an appointment letter: focus on duties and conditions specific to this site, client and scope of work.)" : "") + "\n---\n" + clip(b.doc_text, 60000) + "\n---\n\n" +
          "Suggest specific additions that would make this document meet the client's requirements above and South African " +
          "legislation for this scope of work. Do not repeat anything the document already says. Each addition needs a short " +
          "heading and the text to add (1 to 8 sentences; separate list items with new lines). Add notes for anything that cannot " +
          "be fixed by adding text, such as a missing signature or certificate.\n" +
          "Reply with JSON only, in this form:\n" +
          '{"additions":[{"heading":"...","text":"..."}],"notes":["..."]}',
      }],
    };
  }
  throw new Error("Unknown task.");
}

async function handle(req) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  if (!KEY) return reply({ error: "The AI key has not been set up (ANTHROPIC_API_KEY)." }, 500);
  const auth = req.headers.get("Authorization") || "";
  const apikey = req.headers.get("apikey") || "";
  let body;
  try { body = await req.json(); } catch (_e) { return reply({ error: "Bad request." }, 400); }
  const task = String(body.task || "");

  // 1. Signed in, active, under the daily limit; also writes the activity log entry.
  const begin = await fetch(SB_URL + "/rest/v1/rpc/ai_begin", {
    method: "POST",
    headers: { apikey, Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify({ p_task: task }),
  });
  const bj = await begin.json().catch(() => null);
  if (!begin.ok) {
    const m = (bj && (bj.message || bj.msg)) || "";
    if (/daily AI limit/.test(m)) return reply({ error: "You have reached today's limit for AI requests. Try again tomorrow." }, 429);
    if (/AI allowance used/.test(m)) return reply({ error: "You have used all your AI requests. Ask the administrator if you need more." }, 429);
    if (/AI not enabled/.test(m)) return reply({ error: "The AI functions are not switched on for your account. Ask the administrator." }, 403);
    return reply({ error: "Not allowed. Sign in again." }, begin.status === 401 ? 401 : 403);
  }
  const usageId = bj;

  const refund = () => fetch(SB_URL + "/rest/v1/rpc/ai_refund", {
    method: "POST",
    headers: { apikey, Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify({ p_id: usageId }),
  }).catch(() => null);

  // 2. Build the request for this task only. The browser cannot send its own instructions.
  let t;
  try { t = buildTask(body); } catch (e) { await refund(); return reply({ error: String(e.message || e) }, 400); }

  // 3. Ask Claude (each request is stopped after 140 seconds so the app always gets an answer).
  async function ask(content) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 140000);
    try {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: ctl.signal,
        headers: { "x-api-key": KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: MODEL, max_tokens: t.max, system: SYSTEM, messages: [{ role: "user", content }] }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) throw new Error("The AI service returned an error: " + ((j && j.error && j.error.message) || ("status " + r.status)));
      return j;
    } catch (e) {
      if (e && e.name === "AbortError") throw new Error("The AI took too long to answer. Please try again; if it keeps happening, shorten the scope or the document.");
      throw e;
    } finally { clearTimeout(timer); }
  }
  let j, text;
  try {
    if (t.parts) {
      const rs = await Promise.all(t.parts.map((c) => ask(c)));
      const all = [];
      let cut = false;
      const whole = {};
      rs.forEach((x) => {
        const s = (x.content || []).filter((c) => c.type === "text").map((c) => c.text).join("");
        if (x.stop_reason === "max_tokens") cut = true;
        const a = s.indexOf("{"), z = s.lastIndexOf("}");
        try {
          const o = JSON.parse(s.slice(a, z + 1));
          if (t.merge === "*") Object.keys(o).forEach((k) => { if (!(k in whole)) whole[k] = o[k]; });
          else (o[t.merge] || []).forEach((v) => all.push(v));
        } catch (_e) { cut = true; }
      });
      j = { stop_reason: cut ? "max_tokens" : "end_turn", usage: { input_tokens: rs.reduce((n, x) => n + ((x.usage && x.usage.input_tokens) || 0), 0), output_tokens: rs.reduce((n, x) => n + ((x.usage && x.usage.output_tokens) || 0), 0) } };
      if (t.merge === "*" && !Object.keys(whole).length) throw new Error("The AI reply could not be read. Please try again.");
      let o = {}; if (t.merge === "*") o = whole; else o[t.merge] = all; text = JSON.stringify(o);
    } else {
      j = await ask(t.content);
      text = (j.content || []).filter((c) => c.type === "text").map((c) => c.text).join("");
    }
  } catch (e) {
    await refund();
    return reply({ error: String((e && e.message) || e) + " This request has not been counted." }, 504);
  }

  // 4. Record token use (for cost tracking by the administrator).
  try {
    await fetch(SB_URL + "/rest/v1/rpc/ai_end", {
      method: "POST",
      headers: { apikey, Authorization: auth, "Content-Type": "application/json" },
      body: JSON.stringify({ p_id: usageId, p_in: (j.usage && j.usage.input_tokens) || 0, p_out: (j.usage && j.usage.output_tokens) || 0 }),
    });
  } catch (_e) { /* not critical */ }

  return reply({ text, stop: j.stop_reason });
}

Deno.serve(handle);
