vault_up:
	@docker-compose up -d
	@sleep 3
	@./vault/scripts/vault-init.sh

vault_down:
	@docker-compose down