.PHONY: all build seed lint test run console profile derailed update_lsc attach clean

all: build run

ifeq ($(OS),Windows_NT)
  detectedOS := Windows
else
  detectedOS := $(shell sh -c 'uname -s 2>/dev/null || echo not')
endif

ifeq ($(detectedOS),Linux)
  ifeq ($(shell sh -c 'cat /proc/version | grep --ignore-case --count microsoft'),1)
    detectedOS = WSL
  endif
endif

DOCKER_COMPOSE_CMD := docker compose
docker := docker

ifeq ($(detectedOS),Linux)
  DOCKER_COMPOSE_CMD := sudo --preserve-env docker compose
  docker := sudo --preserve-env docker
endif

container ?= web

build:
	$(DOCKER_COMPOSE_CMD) build web
	$(DOCKER_COMPOSE_CMD) run --rm web bash -c 'bundle install --jobs $$((`nproc` - 1)) && yarn install && rails db:migrate && skylight disable_dev_warning'
	@[ -e tmp/seed ] || make seed
	$(DOCKER_COMPOSE_CMD) stop

seed:
	$(DOCKER_COMPOSE_CMD) run --rm web bash -c "bundle exec rails db:seed"
	@echo "# The presence of this file tells the splits-io Makefile to not re-seed data." > tmp/seed

lint:
	git diff-tree -r --no-commit-id --name-only head origin/master | xargs $(DOCKER_COMPOSE_CMD) run web rubocop --force-exclusion

test:
	$(DOCKER_COMPOSE_CMD) run --rm -e RAILS_ENV=test web bundle exec rspec $(path)

run: # Run DOCKER_COMPOSE_CMD up, but work around Ctrl-C sometimes not stopping containers. See https://github.com/docker/compose/issues/3317#issuecomment-416552656
	bash -c "trap '$(DOCKER_COMPOSE_CMD) stop' EXIT; $(DOCKER_COMPOSE_CMD) up"

console:
	$(DOCKER_COMPOSE_CMD) run --rm web rails console

profile:
	$(DOCKER_COMPOSE_CMD) run --rm -e RAILS_ENV=profiling web rake assets:precompile
	$(DOCKER_COMPOSE_CMD) run --rm -e RAILS_ENV=profiling --service-ports web rails s
	$(DOCKER_COMPOSE_CMD) run --rm -e RAILS_ENV=profiling web rake assets:clobber

derailed:
	$(DOCKER_COMPOSE_CMD) run --rm -e RAILS_ENV=profiling $(env) web bundle exec derailed $(command)

update_lsc:
	$(DOCKER_COMPOSE_CMD) run --rm web bundle exec rake update_lsc

srdc_sync:
	$(DOCKER_COMPOSE_CMD) run --rm web bundle exec rake srdc_sync

attach:
	@echo Do not use ctrl + c to exit this session, use ctrl + p then ctrl + q
	$(docker) attach $(shell $(docker) ps | grep splits-io_$(container)_ | awk '{print $$1}')

clean:
	$(DOCKER_COMPOSE_CMD) down
	rm -rf bundle/
	rm -rf node_modules/
	rm -f tmp/seed

superclean:
	$(DOCKER_COMPOSE_CMD) down --volumes
	rm -rf tmp/seed node_modules bundle
	docker system prune --all --force
	docker builder prune --all --force
