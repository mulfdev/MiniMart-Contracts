include .env
export $(shell sed 's/=.*//' .env)

# --- Argument Parsing Logic (executed when Makefile is parsed) ---
_FIRST_CMD_GOAL  := $(firstword $(MAKECMDGOALS))
_SECOND_CMD_GOAL := $(word 2, $(MAKECMDGOALS))
PARSED_SCRIPT_ARG := # Will hold the script name if a matching command and script are found

# Define commands that expect a script file as the second argument
SCRIPT_EXPECTING_COMMANDS := deploy dry-run deploy-local

# Generalized logic to parse script argument for specified commands
ifeq ($(filter $(_FIRST_CMD_GOAL),$(SCRIPT_EXPECTING_COMMANDS)),$(_FIRST_CMD_GOAL))
    # Check if the second argument looks like a Solidity script file (*.s.sol)
    ifneq ($(filter %.s.sol,$(_SECOND_CMD_GOAL)),)
        PARSED_SCRIPT_ARG := $(_SECOND_CMD_GOAL)
    endif
endif
# --- End Argument Parsing Logic ---

# Common options for forge script (used by 'deploy' and 'dry-run')
# Assumes WALLET_ID and KEYSTORE_PASSWORD are in .env for these commands
# Add --rpc-url $(RPC_URL) if you want to make it explicit or use a different default
FORGE_SCRIPT_OPTS = \
	--account $(WALLET_ID) \
	--password $(KEYSTORE_PASSWORD) \
	--rpc-url $(or $(RPC_URL), http://127.0.0.1:8545) # Default to localhost if RPC_URL not in .env

.PHONY: all compile test lint clean help deploy dry-run deploy-local

all: compile test

compile:
	@echo "Compiling contracts..."
	forge compile

test:
	@echo "Running tests..."
	forge test --match-path "test/*"

lint:
	@echo "Linting Contracts..."
	solhint 'src/**/*.sol'

clean:
	@echo "Cleaning out and cache directories..."
	rm -rf out cache broadcast # Added broadcast to clean

# This rule handles any target ending in .s.sol.
# Its SOLE PURPOSE is to prevent "No rule to make target YourScript.s.sol" errors
# when YourScript.s.sol is passed as an argument.
# It performs NO action.
%.s.sol:
	@: # This is a POSIX-compliant no-op command. It does nothing.

deploy:
	@if [ -z "$(PARSED_SCRIPT_ARG)" ]; then \
		echo "Error: No script file specified or incorrect usage for 'deploy'."; \
		echo "Usage: make deploy YourScript.s.sol"; \
		echo "Ensure YourScript.s.sol is in the script/ directory."; \
		echo "Ensure WALLET_ID, KEYSTORE_PASSWORD, and RPC_URL are set in .env"; \
		exit 1; \
	fi
	@echo "Deploying script/$(PARSED_SCRIPT_ARG)..."
	forge script script/$(PARSED_SCRIPT_ARG) $(FORGE_SCRIPT_OPTS) --broadcast

dry-run:
	@if [ -z "$(PARSED_SCRIPT_ARG)" ]; then \
		echo "Error: No script file specified or incorrect usage for 'dry-run'."; \
		echo "Usage: make dry-run YourScript.s.sol"; \
		echo "Ensure YourScript.s.sol is in the script/ directory."; \
		echo "Ensure WALLET_ID, KEYSTORE_PASSWORD, and RPC_URL are set in .env"; \
		exit 1; \
	fi
	@echo "Dry-running script/$(PARSED_SCRIPT_ARG)..."
	forge script script/$(PARSED_SCRIPT_ARG) $(FORGE_SCRIPT_OPTS)

deploy-local:
	@if [ -z "$(PARSED_SCRIPT_ARG)" ]; then \
		echo "Error: No script file specified or incorrect usage for 'deploy-local'."; \
		echo "Usage: make deploy-local YourScript.s.sol"; \
		echo "Ensure YourScript.s.sol is in the script/ directory."; \
		exit 1; \
	fi
	@echo "Deploying script/$(PARSED_SCRIPT_ARG) to local Anvil..."
	# Default Anvil RPC URL and the first Anvil provided private key
	forge script script/$(PARSED_SCRIPT_ARG) --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Available commands:"
	@echo "  make all           - Compiles contracts and runs tests"
	@echo "  make compile       - Compiles contracts"
	@echo "  make test          - Runs tests"
	@echo "  make lint          - Lints contracts"
	@echo "  make clean         - Cleans build artifacts, cache, and broadcast directories"
	@echo ""
	@echo "Script Execution (requires a script file argument):"
	@echo "  Example: make deploy MyScript.s.sol"
	@echo "  Ensure the script file (e.g., MyScript.s.sol) is located in the 'script/' directory."
	@echo ""
	@echo "  make deploy <YourScript.s.sol>"
	@echo "    Deploys 'script/YourScript.s.sol'."
	@echo "    Uses WALLET_ID, KEYSTORE_PASSWORD, and RPC_URL from .env."
	@echo ""
	@echo "  make dry-run <YourScript.s.sol>"
	@echo "    Dry-runs 'script/YourScript.s.sol'."
	@echo "    Uses WALLET_ID, KEYSTORE_PASSWORD, and RPC_URL from .env."
	@echo ""
	@echo "  make deploy-local <YourScript.s.sol>"
	@echo "    Deploys 'script/YourScript.s.sol' to local Anvil (127.0.0.1:8545)."
	@echo "    Uses a default Anvil private key."
	@echo ""
