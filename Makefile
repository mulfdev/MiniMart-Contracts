include .env

_FIRST_CMD_GOAL  := $(firstword $(MAKECMDGOALS))
_SECOND_CMD_GOAL := $(word 2, $(MAKECMDGOALS))
PARSED_SCRIPT_ARG := # Will hold the script name if a matching command and script are found

SCRIPT_EXPECTING_COMMANDS := deploy-local
ifeq ($(filter $(_FIRST_CMD_GOAL),$(SCRIPT_EXPECTING_COMMANDS)),$(_FIRST_CMD_GOAL))
    ifneq ($(filter %.s.sol,$(_SECOND_CMD_GOAL)),)
        PARSED_SCRIPT_ARG := $(_SECOND_CMD_GOAL)
    endif
endif

.PHONY: deploy-local


%.s.sol:
	@:

deploy-local:
	@if [ -z "$(PARSED_SCRIPT_ARG)" ]; then \
		echo "Error: No script file specified. Usage: make deploy-local YourScript.s.sol"; \
		exit 1; \
	fi
	@echo "Deploying script/$(PARSED_SCRIPT_ARG) to local Anvil..."
	# This rule is already using a private key directly, so it is fine.
	forge script script/$(PARSED_SCRIPT_ARG) --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
