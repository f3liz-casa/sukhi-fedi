export interface NodeInfoResult {
  json: unknown;
}

export async function handleNodeInfo(): Promise<NodeInfoResult> {
  const json = {
    version: "2.1",
    software: {
      name: "sukhi-fedi",
      version: "0.1.0",
    },
    protocols: ["activitypub"],
    usage: {
      users: {
        total: 0,
        activeMonth: 0,
        activeHalfyear: 0,
      },
      localPosts: 0,
    },
    openRegistrations: false,
  };

  return { json };
}
