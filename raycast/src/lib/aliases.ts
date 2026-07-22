import { promises as fs } from "node:fs";
import path from "node:path";
import type { AliasFile, AliasMap } from "./types";

const ROUTING_DIRECTORY = "_routing";
const ALIAS_FILENAME = "project-aliases.json";

export class AliasError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AliasError";
  }
}

export function normalizeAlias(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLocaleLowerCase();
}

export function parseAliases(value: string): string[] {
  const aliases = value.split(",").map(normalizeAlias).filter(Boolean);

  for (const alias of aliases) {
    if (/\s/.test(alias)) throw new AliasError(`"${alias}" contains spaces. Use a short single token.`);
    if (alias.includes("/") || alias.includes("\\")) {
      throw new AliasError(`"${alias}" cannot contain slashes.`);
    }
  }

  return [...new Set(aliases)];
}

export async function readAliases(vaultPath: string): Promise<AliasMap> {
  try {
    const parsed = JSON.parse(await fs.readFile(aliasPath(vaultPath), "utf8")) as Partial<AliasFile>;
    const output: AliasMap = {};
    for (const [projectKey, entry] of Object.entries(parsed.projects ?? {})) {
      output[projectKey] = [...new Set((entry.aliases ?? []).map(normalizeAlias).filter(Boolean))];
    }
    return output;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
    throw new AliasError("Nidus could not read _routing/project-aliases.json.");
  }
}

export async function saveProjectAliases(vaultPath: string, projectKey: string, aliases: string[]): Promise<AliasMap> {
  const current = await readAliases(vaultPath);
  const normalized = [...new Set(aliases.map(normalizeAlias).filter(Boolean))];

  for (const alias of normalized) {
    const owner = Object.entries(current).find(
      ([otherKey, otherAliases]) => otherKey !== projectKey && otherAliases.includes(alias),
    );
    if (owner) throw new AliasError(`"${alias}" is already assigned to ${owner[0]}.`);
  }

  if (normalized.length) current[projectKey] = normalized;
  else delete current[projectKey];

  const file: AliasFile = {
    version: 1,
    projects: Object.fromEntries(
      Object.entries(current)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, projectAliases]) => [key, { aliases: projectAliases }]),
    ),
  };

  const directory = path.join(vaultPath, ROUTING_DIRECTORY);
  await fs.mkdir(directory, { recursive: true });
  await atomicWrite(aliasPath(vaultPath), `${JSON.stringify(file, null, 2)}\n`);
  return current;
}

function aliasPath(vaultPath: string): string {
  return path.join(vaultPath, ROUTING_DIRECTORY, ALIAS_FILENAME);
}

async function atomicWrite(filePath: string, contents: string): Promise<void> {
  const temporary = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  try {
    await fs.writeFile(temporary, contents, { encoding: "utf8", flag: "wx" });
    await fs.rename(temporary, filePath);
  } finally {
    await fs.rm(temporary, { force: true }).catch(() => undefined);
  }
}
