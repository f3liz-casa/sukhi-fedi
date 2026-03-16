import { handleBuildAnnounce, BuildAnnouncePayload, BuildAnnounceResult } from "../build/announce.ts";
import { injectDefined } from "../../fedify/utils.ts";

export interface BuildBoostPayload extends BuildAnnouncePayload {}

export interface BuildBoostResult extends BuildAnnounceResult {}

export async function handleBuildBoost(
  payload: BuildBoostPayload,
): Promise<BuildBoostResult> {
  const result = await handleBuildAnnounce(payload);
  // Inject _misskey_renote_id so Misskey recognises this as a renote
  injectDefined(result.announce as Record<string, unknown>, {
    _misskey_renote_id: payload.object,
  });
  return result;
}
