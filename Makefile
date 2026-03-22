BINARY  := arcline-uptime
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -ldflags "-s -w -X main.version=$(VERSION)"

.PHONY: build clean install run test linux-amd64 linux-arm64 all

build:
	go build $(LDFLAGS) -o $(BINARY) ./cmd/arcline-uptime

linux-amd64:
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BINARY)-linux-amd64 ./cmd/arcline-uptime

linux-arm64:
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BINARY)-linux-arm64 ./cmd/arcline-uptime

all: linux-amd64 linux-arm64

run: build
	./$(BINARY) start --config uptime.example.yaml

test:
	go test ./...

install: build
	install -m 0755 $(BINARY) /usr/local/bin/$(BINARY)

clean:
	rm -f $(BINARY) $(BINARY)-linux-*
