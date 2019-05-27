BIN_DIR     ?= ./bin
DIRS        ?= $(shell find . -name '*.go' | grep --invert-match 'vendor' | xargs -n 1 dirname | sort --unique)
PKG_NAME    ?= app
SCRIPTS_DIR ?= ./scripts

GO_TOOLS = \
	github.com/codegangsta/gin

BFLAGS ?=
LFLAGS ?=
TFLAGS ?=

COVERAGE_PROFILE ?= coverage.out

PSQL := $(shell command -v psql 2> /dev/null)

DATABASE_USER             ?= coresrs_admin
TEST_DATABASE_NAME        ?= coresrs_test
DEVELOPMENT_DATABASE_NAME ?= coresrs

default: build

.PHONY: build
build: install
	@echo "---> Building"
	CGO_ENABLED=0 go build -o $(BIN_DIR)/$(PKG_NAME) -installsuffix cgo -ldflags '-w -s' $(BFLAGS) ./cmd/serve

.PHONY: clean
clean:
	@echo "---> Cleaning"
	go clean

.PHONY: db\:migrate
db\:migrate:
	@echo "---> Migrating"
	go run cmd/migrations/*.go migrate

.PHONY: db\:migrate\:create
db\:migrate\:create:
	@echo "---> Creating new migration"
	go run cmd/migrations/*.go create $(name)

.PHONY: db\:rollback
db\:rollback:
	@echo "---> Rolling back"
	go run cmd/migrations/*.go rollback

.PHONY: db\:seed
db\:seed:
	@echo "---> Populating seeds"
	go run cmd/seeds/*.go

.PHONY: enforce
enforce:
	@echo "---> Enforcing coverage"
	$(SCRIPTS_DIR)/coverage.sh $(COVERAGE_PROFILE)

.PHONY: html
html:
	@echo "---> Generating HTML coverage report"
	go tool cover -html $(COVERAGE_PROFILE)

.PHONY: install
install:
	@echo "---> Installing dependencies"
	go mod download

.PHONY: lint
lint:
	@echo "---> Linting"
	$(BIN_DIR)/golangci-lint run

.PHONY: setup
setup:
	@echo "--> Setting up"
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s -- -b $(BIN_DIR) v1.16.0
	GOBIN=$$(realpath $(BIN_DIR)) go install $(GO_TOOLS)
ifdef PSQL
	dropdb --if-exists $(DEVELOPMENT_DATABASE_NAME)
	dropdb --if-exists $(TEST_DATABASE_NAME)
	dropuser --if-exists $(DATABASE_USER)
	createuser --createdb $(DATABASE_USER)
	createdb -U $(DATABASE_USER) $(TEST_DATABASE_NAME)
	createdb -U $(DATABASE_USER) $(DEVELOPMENT_DATABASE_NAME)
	psql $(DEVELOPMENT_DATABASE_NAME) -c "ALTER DATABASE $(DEVELOPMENT_DATABASE_NAME) SET timezone = 'UTC';"
	psql $(TEST_DATABASE_NAME) -c "ALTER DATABASE $(TEST_DATABASE_NAME) SET timezone = 'UTC';"
	make install
	# make db:migrate
	# ENVIRONMENT=test make db:migrate
	# make db:seed
	# ENVIRONMENT=test make db:seed
else
	$(info Skipping database setup)
endif

.PHONY: start
start:
	@echo "---> Starting"
	DATABASE_DEBUG=true TZ=UTC $(BIN_DIR)/gin --port 7352 --appPort 7353 --path . --build ./cmd/serve --immediate --bin $(BIN_DIR)/gin-$(PKG_NAME) run

.PHONY: test
test:
	@echo "---> Testing"
	GIN_MODE=release ENVIRONMENT=test go test -race ./pkg/... -coverprofile $(COVERAGE_PROFILE) $(TFLAGS)
