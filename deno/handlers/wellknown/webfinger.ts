export interface WebFingerPayload {
  acct: string;
}

export interface WebFingerResult {
  json: unknown;
}

export async function handleWebFinger(payload: WebFingerPayload): Promise<WebFingerResult> {
  const [user, domain] = payload.acct.replace("acct:", "").split("@");

  const json = {
    subject: `acct:${user}@${domain}`,
    links: [
      {
        rel: "self",
        type: "application/activity+json",
        href: `https://${domain}/users/${user}`,
      },
    ],
  };

  return { json };
}
