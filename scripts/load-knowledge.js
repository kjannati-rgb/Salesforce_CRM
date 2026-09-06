#!/usr/bin/env node
/**
 * Knowledge load script — CRM Support agent program (Standard v2 §1).
 * Publishes repo Markdown articles to Salesforce Knowledge. The repo file is
 * canonical; this script is the ONLY sanctioned write path for article content.
 *
 * Usage: node scripts/load-knowledge.js --org KJDEV knowledge/opportunity-stages/*.md
 *
 * Per article:
 *   - parses frontmatter (title, review-date)
 *   - converts Markdown body to HTML (minimal converter, no dependencies)
 *   - upserts by UrlName (= filename): new draft, or editOnlineArticle for updates
 *   - publishes via KbManagement.PublishingService (anonymous Apex through sf CLI)
 *
 * No deletes ever: retiring an article is a manual archive + repo removal.
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const LANGUAGE = 'en_US';

function parseArgs(argv) {
  const files = [];
  let org = null;
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--org') org = argv[++i];
    else files.push(argv[i]);
  }
  if (!org || files.length === 0) {
    console.error('Usage: node scripts/load-knowledge.js --org <alias> <file.md> [...]');
    process.exit(1);
  }
  return { org, files };
}

function parseFrontmatter(src) {
  const m = src.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!m) throw new Error('missing frontmatter');
  const fm = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([a-z-]+):\s*(.+)$/);
    if (kv) fm[kv[1]] = kv[2].trim();
  }
  return { fm, body: m[2] };
}

function esc(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/\*([^*]+)\*/g, '<i>$1</i>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
}

/** Minimal Markdown -> HTML: headings, tables, lists, hr, paragraphs. */
function mdToHtml(md) {
  const lines = md.split(/\r?\n/);
  const out = [];
  let list = null; // 'ul' | 'ol'
  let table = [];
  const closeList = () => { if (list) { out.push(`</${list}>`); list = null; } };
  const flushTable = () => {
    if (!table.length) return;
    const rows = table.filter(r => !/^\s*\|?[\s|:-]+\|?\s*$/.test(r));
    out.push('<table border="1" cellpadding="4" cellspacing="0">');
    rows.forEach((r, i) => {
      const cells = r.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split('|').map(c => inline(c.trim()));
      const tag = i === 0 ? 'th' : 'td';
      out.push('<tr>' + cells.map(c => `<${tag}>${c}</${tag}>`).join('') + '</tr>');
    });
    out.push('</table>');
    table = [];
  };
  for (const raw of lines) {
    const line = raw.replace(/\s+$/, '');
    if (/^\s*\|.*\|/.test(line)) { closeList(); table.push(line); continue; }
    flushTable();
    if (line === '') { closeList(); continue; }
    let m;
    if ((m = line.match(/^(#{1,4})\s+(.*)$/))) { closeList(); const h = m[1].length + 1; out.push(`<h${h}>${inline(m[2])}</h${h}>`); }
    else if (/^---+$/.test(line)) { closeList(); out.push('<hr/>'); }
    else if ((m = line.match(/^[-*]\s+(.*)$/))) { if (list !== 'ul') { closeList(); out.push('<ul>'); list = 'ul'; } out.push(`<li>${inline(m[1])}</li>`); }
    else if ((m = line.match(/^\d+\.\s+(.*)$/))) { if (list !== 'ol') { closeList(); out.push('<ol>'); list = 'ol'; } out.push(`<li>${inline(m[1])}</li>`); }
    else { closeList(); out.push(`<p>${inline(line)}</p>`); }
  }
  closeList(); flushTable();
  return out.join('\n');
}

function apexString(s) {
  // Apex string literals cap at 32k per literal; concatenate chunks.
  const escd = s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\r/g, '').replace(/\n/g, '\\n');
  const chunks = [];
  for (let i = 0; i < escd.length; i += 8000) chunks.push("'" + escd.slice(i, i + 8000) + "'");
  return chunks.join('\n  + ');
}

function runApex(org, apex) {
  const tmp = path.join(os.tmpdir(), `load-kb-${Date.now()}.apex`);
  fs.writeFileSync(tmp, apex, 'utf8');
  try {
    const res = execFileSync('sf', ['apex', 'run', '-o', org, '-f', tmp, '--json'],
      { encoding: 'utf8', shell: process.platform === 'win32' });
    const j = JSON.parse(res);
    if (!j.result || j.result.success !== true) {
      throw new Error(j.result ? (j.result.exceptionMessage || j.result.compileProblem || 'apex failed') : res);
    }
  } finally { fs.unlinkSync(tmp); }
}

const { org, files } = parseArgs(process.argv);

for (const file of files) {
  const { fm, body } = parseFrontmatter(fs.readFileSync(file, 'utf8'));
  if (!fm.title) throw new Error(`${file}: frontmatter needs title`);
  if (!fm['review-date']) throw new Error(`${file}: frontmatter needs review-date`);
  const urlName = path.basename(file, '.md');
  if (!/^[A-Za-z0-9-]+$/.test(urlName)) throw new Error(`${file}: filename must be a valid UrlName`);
  const html = mdToHtml(body);
  const title = fm.title.slice(0, 255);

  const apex = `
String urlName = '${urlName}';
List<Knowledge__kav> online = [SELECT Id, KnowledgeArticleId FROM Knowledge__kav
  WHERE UrlName = :urlName AND PublishStatus = 'Online' AND Language = '${LANGUAGE}' LIMIT 1];
Id draftId;
if (!online.isEmpty()) {
  draftId = KbManagement.PublishingService.editOnlineArticle(online[0].KnowledgeArticleId, false);
} else {
  List<Knowledge__kav> draft = [SELECT Id FROM Knowledge__kav
    WHERE UrlName = :urlName AND PublishStatus = 'Draft' AND Language = '${LANGUAGE}' LIMIT 1];
  if (!draft.isEmpty()) { draftId = draft[0].Id; }
  else {
    Knowledge__kav kav = new Knowledge__kav(UrlName = urlName, Language = '${LANGUAGE}', Title = 'placeholder');
    insert kav;
    draftId = kav.Id;
  }
}
Knowledge__kav d = new Knowledge__kav(Id = draftId);
d.Title = ${apexString(title)};
d.Summary = ${apexString('Maintained in source control — do not edit here. Source: ' + file.replace(/\\/g, '/'))};
d.Answer__c = ${apexString(html)};
d.Review_Date__c = Date.valueOf('${fm['review-date']}');
update d;
Knowledge__kav pub = [SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :draftId];
KbManagement.PublishingService.publishArticle(pub.KnowledgeArticleId, true);
System.debug('PUBLISHED ' + urlName);
`;
  runApex(org, apex);
  console.log(`published: ${urlName} (${title})`);
}
console.log('done.');
