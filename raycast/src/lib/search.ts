import type { AliasMap, ProjectRecord } from "./types";
import { normalizeAlias } from "./aliases";

export function rankProjects(
  projects: ProjectRecord[],
  query: string,
  aliases: AliasMap,
  recentProjectKeys: string[],
): ProjectRecord[] {
  const normalizedQuery = normalizeAlias(query);
  const recentIndex = new Map(recentProjectKeys.map((key, index) => [key, index]));

  const ranked = projects
    .map((project) => ({
      project,
      score: normalizedQuery ? projectScore(project, normalizedQuery, aliases[project.key] ?? []) : 1,
      recent: recentIndex.get(project.key) ?? Number.MAX_SAFE_INTEGER,
    }))
    .filter((entry) => entry.score > 0);

  ranked.sort(
    (a, b) =>
      b.score - a.score ||
      a.recent - b.recent ||
      b.project.lastActivity - a.project.lastActivity ||
      a.project.name.localeCompare(b.project.name),
  );
  return ranked.map((entry) => entry.project);
}

export function projectForExactAlias(
  projects: ProjectRecord[],
  aliases: AliasMap,
  input: string,
): ProjectRecord | undefined {
  const alias = normalizeAlias(input);
  if (!alias) return undefined;
  return projects.find((project) => (aliases[project.key] ?? []).includes(alias));
}

function projectScore(project: ProjectRecord, query: string, aliases: string[]): number {
  if (aliases.includes(query)) return 10_000;

  const aliasScore = Math.max(0, ...aliases.map((alias) => fuzzyScore(query, alias)));
  const name = normalizeAlias(project.name);
  const discipline = normalizeAlias(project.disciplineName);

  if (name === query) return 9_500;
  if (name.startsWith(query)) return 9_000 - Math.min(name.length - query.length, 500);

  const nameFuzzy = fuzzyScore(query, name);
  if (nameFuzzy) return 6_000 + nameFuzzy;
  if (aliasScore) return 7_000 + aliasScore;

  if (discipline === query) return 4_000;
  if (discipline.startsWith(query)) return 3_800;
  const disciplineFuzzy = fuzzyScore(query, discipline);
  return disciplineFuzzy ? 3_000 + disciplineFuzzy : 0;
}

function fuzzyScore(query: string, candidate: string): number {
  if (!query || !candidate) return 0;
  let queryIndex = 0;
  let score = 0;
  let streak = 0;

  for (let index = 0; index < candidate.length && queryIndex < query.length; index += 1) {
    if (candidate[index] !== query[queryIndex]) {
      streak = 0;
      continue;
    }
    streak += 1;
    score += 10 + streak * 4;
    if (index === 0 || /[\s-_]/.test(candidate[index - 1])) score += 18;
    queryIndex += 1;
  }

  if (queryIndex !== query.length) return 0;
  return score - Math.max(0, candidate.length - query.length);
}
