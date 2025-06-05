include .env
export $(shell sed 's/=.*//' .env)

# --- Argument Parsing Logic (executed when Makefile is parsed) ---
# _FIRST_CMD_GOAL: The first word after 'make' (e.g., "deploy", "dry-run")
# _SECOND_CMD_GOAL: The second word (e.g., "YourScript.s.sol" or empty)
# PARSED_SCRIPT_ARG: Will hold the script name if 'deploy <script>' or 'dry-run <script>' is used.
_FIRST_CMD_GOAL := $(firstword $(MAKECMDGOALS))
_SECOND_CMD_GOAL := $(word 2, $(MAKECMDGOALS))
PARSED_SCRIPT_ARG :=

# Check if the command pattern is 'deploy <script.s.sol>'
ifeq ($(_FIRST_CMD_GOAL),deploy)
    ifneq ($(filter %.s.sol,$(_SECOND_CMD_GOAL)),) # Is the second arg a script file?
        PARSED_SCRIPT_ARG := $(_SECOND_CMD_GOAL)
    endif
endif

# Check if the command pattern is 'dry-run <script.s.sol>'
ifeq ($(_FIRST_CMD_GOAL),dry-run)
    ifneq ($(filter %.s.sol,$(_SECOND_CMD_GOAL)),) # Is the second arg a script file?
        PARSED_SCRIPT_ARG := $(_SECOND_CMD_GOAL)
    endif
endif
# --- End Argument Parsing Logic ---

# Common options for forge script
FORGE_SCRIPT_OPTS = \
	--account $(WALLET_ID) \
	--password $(KEYSTORE_PASSWORD)

.PHONY: all compile test lint clean help deploy dry-run

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
	rm -rf out cache

# This rule handles any target ending in .s.sol.
# Its SOLE PURPOSE is to prevent "No rule to make target YourScript.s.sol" errors
# when YourScript.s.sol is passed as an argument to 'deploy' or 'dry-run'.
# It performs NO action.
%.s.sol:
	@: # This is a POSIX-compliant no-op command. It does nothing.

deploy:
	@if [ -z "$(PARSED_SCRIPT_ARG)" ]; then \
		echo "Error: No script file specified or incorrect usage for 'deploy'."; \
		echo "Usage: make deploy YourScript.s.sol"; \
		exit 1; \
	fi
	@echo "Deploying script/$(PARSED_SCRIPT_ARG)..."
	forge script script/$(PARSED_SCRIPT_ARG) $(FORGE_SCRIPT_OPTS) --broadcast

dry-run:
	@if [ -z "$(PARSED_SCRIPT_ARG)" ]; then \
		echo "Error: No script file specified or incorrect usage for 'dry-run'."; \
		echo "Usage: make dry-run YourScript.s.sol"; \
		exit 1; \
	fi
	@echo "Dry-running script/$(PARSED_SCRIPT_ARG)..."
	forge script script/$(PARSED_SCRIPT_ARG) $(FORGE_SCRIPT_OPTS)

help:
	@echo "Available commands:"
	@echo "  make compile       - Compiles contracts"
	@echo "  make test          - Runs tests"
	@echo "  make lint          - Lints contracts"
	@echo "  make clean         - Cleans build artifacts"
	@echo ""
	@echo "Script Execution (explicit command required):"
	@echo "  make deploy <YourScript.s.sol>       - Deploys script/YourScript.s.sol"
	@echo "  make dry-run <YourScript.s.sol>      - Dry-runs script/YourScript.s.sol"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy MyAwesomeContract.s.sol"
	@echo "  make dry-run TestSetup.s.sol"
