.DEFAULT_GOAL := help
.PHONY: help up up-ui verify down

help:     ## show this usage (default target)
	@echo "reShapr on apple/container"
	@echo
	@echo "Usage: make <target>"
	@echo
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-8s %s\n", $$1, $$2}'
	@echo
	@echo "Ports: RESHAPR_CTRL_HOST_PORT (5555), RESHAPR_GATEWAY_HOST_PORT (7777), RESHAPR_UI_HOST_PORT (3333)"
	@echo "Typical run: make up-ui && make verify && make down"

up:       ## start postgres, control plane and gateway on apple/container
	./scripts/up.sh

up-ui:    ## same as up, plus the web UI on port 3333
	./scripts/up.sh --ui

verify:   ## import Open-Meteo and run the MCP smoke test
	./scripts/verify.sh

down:     ## remove the containers (run before a new up)
	./scripts/down.sh

Makefile: ;

%:        # anything else: say so and print the usage
	@echo "make: unknown target '$@'"; echo
	@$(MAKE) --no-print-directory help
	@exit 1
