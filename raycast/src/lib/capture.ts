import { promises as fs } from "node:fs";
import { randomUUID } from "node:crypto";
import path from "node:path";
import type { CaptureInput, ProjectRecord } from "./types";

const NOTE_SEPARATOR = "--";
const TASK_PREFIX = /^t-\s*/i;
const MAX_WRITE_ATTEMPTS = 3;

export function hasTaskPrefix(value: string): boolean {
  return TASK_PREFIX.test(value.trim());
}

export function parseCaptureInput(
  value: string,
  defaultDestination: CaptureInput["destination"] = "inbox",
): CaptureInput | null {
  let content = value.trim();
  if (!content) return null;

  const explicitTask = TASK_PREFIX.test(content);
  const destination = explicitTask ? "task" : defaultDestination;
  if (explicitTask) content = content.replace(TASK_PREFIX, "").trim();
  if (!content) return null;

  const separatorIndex = content.indexOf(NOTE_SEPARATOR);
  const title = cleanTitle(separatorIndex >= 0 ? content.slice(0, separatorIndex) : content);
  if (!title) return null;

  return {
    destination,
    title,
    body: separatorIndex >= 0 ? content.slice(separatorIndex + NOTE_SEPARATOR.length).trim() : "",
  };
}

export async function appendCapture(project: ProjectRecord, capture: CaptureInput): Promise<void> {
  const destinationPath = capture.destination === "task" ? project.tasksPath : project.inboxPath;
  const folder = path.dirname(destinationPath);
  const folderStat = await fs.stat(folder).catch(() => null);
  if (!folderStat?.isDirectory()) throw new Error(`The project folder for ${project.name} no longer exists.`);

  for (let attempt = 0; attempt < MAX_WRITE_ATTEMPTS; attempt += 1) {
    const before = await readDestination(destinationPath, capture.destination);
    const output = before + cardBlock(capture);
    const temporary = `${destinationPath}.${process.pid}.${Date.now()}.${attempt}.tmp`;

    try {
      await fs.writeFile(temporary, output, { encoding: "utf8", flag: "wx" });
      const current = await readDestination(destinationPath, capture.destination);
      if (current !== before) continue;
      await fs.rename(temporary, destinationPath);
      return;
    } finally {
      await fs.rm(temporary, { force: true }).catch(() => undefined);
    }
  }

  throw new Error("The Inbox changed while Nidus was writing. Try the capture again.");
}

function cardBlock(capture: CaptureInput): string {
  const now = new Date().toISOString();
  const metadata = {
    images: [],
    id: randomUUID().toUpperCase(),
    created: now,
    extra: {},
    links: [],
    modified: now,
    origin: capture.destination === "task" ? "task-manager" : "inbox",
  };
  const body = capture.body ? `\n${capture.body}\n` : "";
  return `\n## ${capture.title}\n<!-- nidus:${JSON.stringify(metadata)} -->\n${body}`;
}

function cleanTitle(value: string): string {
  return value.trim().replace(/[\r\n]+/g, " ");
}

async function readDestination(filePath: string, destination: CaptureInput["destination"]): Promise<string> {
  try {
    return await fs.readFile(filePath, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return destination === "task" ? "# Tasks\n" : "# Inbox\n";
    }
    throw error;
  }
}
