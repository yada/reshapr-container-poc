.PHONY: up verify down

up:       ## start postgres, control plane and gateway on apple/container
	./scripts/up.sh

verify:   ## import Open-Meteo and run the MCP smoke test
	./scripts/verify.sh

down:     ## remove the containers
	./scripts/down.sh
