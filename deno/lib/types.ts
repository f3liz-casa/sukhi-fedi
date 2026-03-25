// Shared Hono environment type used across all route modules.

export type Account = {
  id: string;
  username: string;
  is_admin: boolean;
};

/** Hono generic env — all route files use `Hono<AppEnv>` */
export type AppEnv = {
  Variables: {
    account: Account;
  };
};
