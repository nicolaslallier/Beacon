# ------------------------------------------------------------------
# Release/Deploy
# ------------------------------------------------------------------
.PHONY: push

push:
	@echo "Pushing $(FULL_IMAGE):$(VERSION)..."
	$(DOCKER) push "$(FULL_IMAGE):$(VERSION)"
	$(DOCKER) push "$(FULL_IMAGE):latest"
