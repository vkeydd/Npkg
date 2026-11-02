CC = nim
SRC = npkg.nim
BIN = npkg
PREFIX ?= /usr/local
INSTALL_DIR = /opt/npkg

.PHONY: all build clean install uninstall

all: build

build:
	@echo "Building $(BIN) with Nim (release mode)..."
	$(CC) c -d:release --opt:speed -d:ssl $(SRC)
install: build
	@echo "Installing $(BIN) system-wide..."
	install -Dm755 $(BIN) $(PREFIX)/bin/$(BIN)
	mkdir -p $(INSTALL_DIR)
	@echo "Successfully installed!"

uninstall:
	@echo "Uninstalling $(BIN)..."
	rm -f $(PREFIX)/bin/$(BIN)
	@echo "Successfully uninstalled."

clean:
	@echo "Cleaning build artifacts..."
	rm -f $(BIN)
	rm -rf nimcache/
