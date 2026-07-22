import { getPreferenceValues } from "@raycast/api";
import { promises as fs } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import type { NidusConfig, ProjectRecord } from "./types";

type VaultPreferences = {
  vaultPath?: string;
};

const SIDECAR_PATH = path.join(homedir(), "Library", "Application Support", "Nidus", "vault-path.txt");

export class VaultError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VaultError";
  }
}

export async function resolveVaultPath(): Promise<string> {
  const preference = getPreferenceValues<VaultPreferences>().vaultPath?.trim();
  const candidate = preference || (await readSidecar());
  const vaultPath = path.resolve(candidate);

  try {
    const stat = await fs.stat(path.join(vaultPath, "nidus.json"));
    if (!stat.isFile()) throw new Error("not a file");
  } catch {
    throw new VaultError(
      preference
        ? "The configured folder is not a Nidus vault because it has no nidus.json."
        : "Open Nidus once to create its vault sidecar, or set Vault Path in the extension preferences.",
    );
  }

  return vaultPath;
}

export async function loadProjectCatalog(): Promise<{ vaultPath: string; projects: ProjectRecord[] }> {
  const vaultPath = await resolveVaultPath();
  const config = await readConfig(vaultPath);
  const projects = (
    await Promise.all(
      (config.disciplines ?? []).flatMap((discipline) =>
        (discipline.projects ?? []).map(async (project): Promise<ProjectRecord | null> => {
          if (!discipline.id || !discipline.folder || !project.id || !project.name || !project.folder) return null;

          const folderPath = resolveInside(vaultPath, discipline.folder, project.folder);
          try {
            if (!(await fs.stat(folderPath)).isDirectory()) return null;
          } catch {
            return null;
          }

          const inboxSlot = project.layout?.grid?.find((slot) => slot.tool === "inbox");
          const inboxFilename = inboxSlot?.files?.[0] || "inbox.md";
          const inboxPath = resolveInside(folderPath, inboxFilename);
          const taskSlot =
            project.layout?.grid?.find((slot) => slot.id === "task-manager") ??
            project.layout?.grid?.find((slot) => slot.tool === "task-manager");
          const tasksFilename = taskSlot?.files?.[0] || "tasks-todo.md";
          const tasksPath = resolveInside(folderPath, tasksFilename);

          return {
            key: `${discipline.id}/${project.id}`,
            id: project.id,
            name: project.name,
            description: project.description,
            disciplineId: discipline.id,
            disciplineName: discipline.name,
            folderPath,
            inboxPath,
            tasksPath,
            lastActivity: await latestProjectActivity(folderPath),
          };
        }),
      ),
    )
  ).filter((project): project is ProjectRecord => project !== null);

  return { vaultPath, projects };
}

function resolveInside(root: string, ...segments: string[]): string {
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(resolvedRoot, ...segments);
  if (resolved !== resolvedRoot && !resolved.startsWith(`${resolvedRoot}${path.sep}`)) {
    throw new VaultError("A project path escapes the Nidus vault.");
  }
  return resolved;
}

async function readSidecar(): Promise<string> {
  try {
    const value = (await fs.readFile(SIDECAR_PATH, "utf8")).trim();
    if (!value) throw new Error("empty sidecar");
    return value;
  } catch {
    throw new VaultError(
      "Open Nidus once to create its vault sidecar, or set Vault Path in the extension preferences.",
    );
  }
}

async function readConfig(vaultPath: string): Promise<NidusConfig> {
  try {
    return JSON.parse(await fs.readFile(path.join(vaultPath, "nidus.json"), "utf8")) as NidusConfig;
  } catch {
    throw new VaultError("Nidus could not read nidus.json. Check that the vault configuration is valid JSON.");
  }
}

async function latestProjectActivity(folderPath: string): Promise<number> {
  try {
    const entries = await fs.readdir(folderPath, { withFileTypes: true });
    const timestamps = await Promise.all(
      entries.slice(0, 500).map(async (entry) => {
        try {
          return (await fs.stat(path.join(folderPath, entry.name))).mtimeMs;
        } catch {
          return 0;
        }
      }),
    );
    return Math.max((await fs.stat(folderPath)).mtimeMs, ...timestamps);
  } catch {
    return 0;
  }
}
