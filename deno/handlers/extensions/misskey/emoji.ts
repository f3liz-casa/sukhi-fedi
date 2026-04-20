import { Emoji, Image } from "@fedify/fedify";
import { serialize, injectDefined } from "../../../fedify/utils.ts";

export interface BuildMisskeyEmojiPayload {
  name: string;
  iconUrl: string;
  license?: string;
  actorId: string;
}

export interface BuildMisskeyEmojiResult {
  emoji: unknown;
}

export async function handleBuildMisskeyEmoji(
  payload: BuildMisskeyEmojiPayload,
): Promise<BuildMisskeyEmojiResult> {
  const emoji = new Emoji({
    id: new URL(`${payload.actorId}#emoji-${payload.name}`),
    name: payload.name,
    icon: new Image({
      url: new URL(payload.iconUrl),
      mediaType: "image/png",
    }),
  });
  const emojiJson = await serialize(emoji) as Record<string, unknown>;
  // Inject _misskey_license for custom emoji license info
  injectDefined(emojiJson, { _misskey_license: payload.license });
  return { emoji: emojiJson };
}
