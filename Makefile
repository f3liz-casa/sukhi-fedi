.PHONY: preflight check push-static push-styles

DEPLOY_HOST ?= 217.142.242.103
DEPLOY_USER ?= rocky
STATIC_DIR  ?= /var/lib/sukhi-fedi/static

preflight:
	@bash infra/preflight.sh

check:
	@bash scripts/check_presets_sync.sh

# Rebuild the SPA locally and rsync the result to the host override
# dir. Gateway serves /static/* and /_app/* from there before falling
# back to the image-baked priv/static, so this lands instantly ─ no
# image rebuild, no container reboot. Same for `make push-styles`
# which is the lighter "only the raw token CSS" variant.
push-static:
	cd web && npm run build
	ssh $(DEPLOY_USER)@$(DEPLOY_HOST) "sudo mkdir -p $(STATIC_DIR) && sudo chown $(DEPLOY_USER) $(STATIC_DIR)"
	rsync -av --delete web/build/ $(DEPLOY_USER)@$(DEPLOY_HOST):$(STATIC_DIR)/
	rsync -av web/src/styles/ $(DEPLOY_USER)@$(DEPLOY_HOST):$(STATIC_DIR)/styles/

push-styles:
	ssh $(DEPLOY_USER)@$(DEPLOY_HOST) "sudo mkdir -p $(STATIC_DIR)/styles && sudo chown -R $(DEPLOY_USER) $(STATIC_DIR)"
	rsync -av web/src/styles/ $(DEPLOY_USER)@$(DEPLOY_HOST):$(STATIC_DIR)/styles/
