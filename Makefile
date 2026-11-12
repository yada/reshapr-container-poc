.PHONY: up up-ui verify down

up:       ## start postgres, control plane and gateway on apple/container
	./scripts/up.sh

up-ui:    ## same as up, plus the web UI on port 3333
	./scripts/up.sh --ui

verify:   ## import Open-Meteo and run the MCP smoke test
	./scripts/verify.sh

down:     ## remove the containers
	./scripts/down.sh
