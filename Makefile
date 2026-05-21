.PHONY: preflight check

preflight:
	@bash infra/preflight.sh

check:
	@bash scripts/check_presets_sync.sh
