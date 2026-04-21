#!/usr/bin/env bash
# Populate terraform.tfvars for the x64 free-tier stack by pulling values
# from ~/.oci/config and the OCI API. Prompts only for the values that
# can't be auto-discovered.
#
# Requires: oci (>= 3.0), jq
# Usage:    ./bootstrap-tfvars.sh [--profile DEFAULT] [--force]

set -euo pipefail

PROFILE=""
PROFILE_EXPLICIT=0
FORCE=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/terraform.tfvars"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; PROFILE_EXPLICIT=1; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for bin in oci jq python3; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

if [[ -f "$OUT" && $FORCE -ne 1 ]]; then
  echo "$OUT already exists. Re-run with --force to overwrite." >&2
  exit 1
fi

CFG="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"
[[ -f "$CFG" ]] || { echo "no OCI config at $CFG. Run: oci setup config" >&2; exit 1; }

# ── Profile auto-detection ────────────────────────────────────────────────────
# If --profile wasn't explicitly passed, pick DEFAULT if it has the required
# keys, otherwise fall back to the single named profile (if there is exactly
# one). This matches how users actually configure OCI CLI with named profiles.
if [[ $PROFILE_EXPLICIT -eq 0 ]]; then
  DETECT=$(python3 - "$CFG" <<'PY'
import configparser, os, sys
c = configparser.RawConfigParser()
c.optionxform = str
c.read(os.path.expanduser(sys.argv[1]))
required = {"tenancy", "user", "fingerprint", "key_file", "region"}
if c.defaults() and required.issubset(c.defaults().keys()):
    print("OK DEFAULT")
else:
    named = [s for s in c.sections() if required.issubset(c[s].keys())]
    if len(named) == 1:
        print(f"OK {named[0]}")
    elif len(named) > 1:
        print(f"AMBIGUOUS {','.join(named)}")
    else:
        all_sections = (["DEFAULT"] if c.defaults() else []) + c.sections()
        print(f"NONE {','.join(all_sections)}")
PY
  )
  case "$DETECT" in
    OK\ *)
      PROFILE="${DETECT#OK }"
      echo "(auto-selected profile: $PROFILE)"
      ;;
    AMBIGUOUS\ *)
      echo "Multiple profiles in $CFG have all required keys: ${DETECT#AMBIGUOUS }" >&2
      echo "Pass --profile NAME to pick one." >&2
      exit 1
      ;;
    NONE\ *)
      echo "No profile in $CFG has all required keys." >&2
      echo "  Present profiles: ${DETECT#NONE }" >&2
      echo "  Required keys:    tenancy, user, fingerprint, key_file, region" >&2
      echo "Run 'oci setup config' to (re)generate the file." >&2
      exit 1
      ;;
  esac
fi

# ── Parse ~/.oci/config [PROFILE] ─────────────────────────────────────────────
# Use Python configparser so that INI quirks (CRLF, whitespace, comments,
# inline indentation) are handled by the stdlib rather than our awk regex.
get_cfg() {
  python3 - "$CFG" "$PROFILE" "$1" <<'PY'
import configparser, os, sys
cfg_path, profile, key = sys.argv[1], sys.argv[2], sys.argv[3]
c = configparser.RawConfigParser()
c.optionxform = str
c.read(os.path.expanduser(cfg_path))
if profile in c and key in c[profile]:
    print(c[profile][key].strip())
PY
}

dump_profile() {
  python3 - "$CFG" "$PROFILE" <<'PY' >&2
import configparser, os, sys
c = configparser.RawConfigParser()
c.optionxform = str
c.read(os.path.expanduser(sys.argv[1]))
profile = sys.argv[2]
# DEFAULT is a pseudo-section and not included in .sections(); add it
# back so users see all available profile names.
profiles = (["DEFAULT"] if c.defaults() else []) + c.sections()
print(f"--- Available profiles: {profiles}")
if profile in c:
    print(f"--- Keys in [{profile}]: {list(c[profile].keys())}")
else:
    print(f"--- Profile [{profile}] not found.")
PY
}

TENANCY=$(get_cfg tenancy)
USER_OCID=$(get_cfg user)
FINGERPRINT=$(get_cfg fingerprint)
KEY_FILE=$(get_cfg key_file)
REGION=$(get_cfg region)

cfg_key_for() {
  case "$1" in
    TENANCY) echo "tenancy" ;;
    USER_OCID) echo "user" ;;
    FINGERPRINT) echo "fingerprint" ;;
    KEY_FILE) echo "key_file" ;;
    REGION) echo "region" ;;
  esac
}
for name in TENANCY USER_OCID FINGERPRINT KEY_FILE REGION; do
  if [[ -z "${!name}" ]]; then
    echo "missing '$(cfg_key_for "$name")' in $CFG [$PROFILE]" >&2
    dump_profile
    echo "Run 'oci setup config' to (re)generate the file." >&2
    exit 1
  fi
done

# expand ~ in key_file
KEY_FILE="${KEY_FILE/#\~/$HOME}"

echo "profile   : $PROFILE"
echo "region    : $REGION"
echo "tenancy   : $TENANCY"

# ── Tenancy namespace (for OCIR) ──────────────────────────────────────────────
NS=$(oci os ns get --profile "$PROFILE" --query 'data' --raw-output)
echo "namespace : $NS"

# ── Compartment: let the user pick, default to tenancy root ──────────────────
echo
echo "Available compartments (top level):"
COMPS_JSON=$(oci iam compartment list \
  --compartment-id "$TENANCY" \
  --profile "$PROFILE" \
  --all \
  --query 'data[?"lifecycle-state"==`ACTIVE`].{name:name, id:id}' 2>/dev/null || echo '[]')

COMP_NAMES=()
while IFS= read -r line; do COMP_NAMES+=("$line"); done < <(echo "$COMPS_JSON" | jq -r '.[].name')
COMP_IDS=()
while IFS= read -r line; do COMP_IDS+=("$line"); done < <(echo "$COMPS_JSON" | jq -r '.[].id')

echo "  0) <root> (tenancy itself)"
for i in "${!COMP_NAMES[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${COMP_NAMES[$i]}"
done

read -r -p "Pick compartment [0]: " COMP_IDX
COMP_IDX="${COMP_IDX:-0}"
if [[ "$COMP_IDX" == "0" ]]; then
  COMPARTMENT="$TENANCY"
else
  COMPARTMENT="${COMP_IDS[$((COMP_IDX-1))]}"
fi

# ── Availability domain ───────────────────────────────────────────────────────
echo
echo "Availability domains in $REGION:"
ADS_JSON=$(oci iam availability-domain list \
  --compartment-id "$TENANCY" \
  --profile "$PROFILE" \
  --query 'data[].name')

AD_NAMES=()
while IFS= read -r line; do AD_NAMES+=("$line"); done < <(echo "$ADS_JSON" | jq -r '.[]')
for i in "${!AD_NAMES[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${AD_NAMES[$i]}"
done
read -r -p "Pick AD [1]: " AD_IDX
AD_IDX="${AD_IDX:-1}"
AD="${AD_NAMES[$((AD_IDX-1))]}"

# ── Free-form prompts ─────────────────────────────────────────────────────────
read -r -p "Domain (e.g. nodeinfo-watch.example.tld): " DOMAIN
read -r -p "SSH public key path [$HOME/.ssh/id_ed25519.pub]: " SSH_PUB
SSH_PUB="${SSH_PUB:-$HOME/.ssh/id_ed25519.pub}"
[[ -f "$SSH_PUB" ]] || { echo "missing SSH pub key: $SSH_PUB" >&2; exit 1; }

# ── Write tfvars ──────────────────────────────────────────────────────────────
cat > "$OUT" <<TFVARS
# Auto-generated by bootstrap-tfvars.sh from ~/.oci/config [$PROFILE].
# NEVER commit this file — it references your API key.

tenancy_ocid        = "$TENANCY"
user_ocid           = "$USER_OCID"
fingerprint         = "$FINGERPRINT"
private_key_path    = "$KEY_FILE"
region              = "$REGION"
compartment_ocid    = "$COMPARTMENT"
tenancy_namespace   = "$NS"
domain              = "$DOMAIN"
availability_domain = "$AD"
ssh_public_key_path = "$SSH_PUB"
TFVARS

chmod 0600 "$OUT"
echo
echo "wrote $OUT (mode 0600)"
