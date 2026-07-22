export type ToolSlot = {
  id?: string;
  tool?: string;
  files?: string[];
};

export type NidusProjectConfig = {
  id: string;
  name: string;
  folder: string;
  description?: string;
  layout?: {
    grid?: ToolSlot[];
  };
};

export type NidusDisciplineConfig = {
  id: string;
  name: string;
  folder: string;
  projects?: NidusProjectConfig[];
};

export type NidusConfig = {
  disciplines?: NidusDisciplineConfig[];
};

export type ProjectRecord = {
  key: string;
  id: string;
  name: string;
  description?: string;
  disciplineId: string;
  disciplineName: string;
  folderPath: string;
  inboxPath: string;
  tasksPath: string;
  lastActivity: number;
};

export type AliasFile = {
  version: 1;
  projects: Record<string, { aliases: string[] }>;
};

export type AliasMap = Record<string, string[]>;

export type CaptureInput = {
  destination: "inbox" | "task";
  title: string;
  body: string;
};
