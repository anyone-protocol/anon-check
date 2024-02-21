SHELL := /bin/bash

start: exits
	@./check

collector_url = ${COLLECTOR_HOST}/recent/
consensuses_dir = relay-descriptors/consensuses/
#exit_lists_dir = exit-lists/
descriptors_dir = relay-descriptors/server-descriptors/

data/:
	@mkdir -p data

data/descriptors/: data/
	@mkdir -p data/descriptors

data/consensuses/: data/
	@mkdir -p data/consensuses

#data/exit-lists/: data/
#	@mkdir -p data/exit-lists

data/consensus: data/consensuses/
	@echo "Getting latest consensus documents"
	@find data/consensuses -mtime +31 | xargs rm -f
	@pushd data/consensuses/; \
		wget -r -nH -nd -nc --no-parent --reject "index.html*" \
			$(collector_url)$(consensuses_dir); \
		popd
	@echo Consensuses written

#TODO - exit-addresses is based on TorDNSEL, which is not working now. All TorDNSEL code is commented out
#data/exit-addresses: data/exit-lists/
#	@echo "Getting latest exit lists"
#	@find data/exit-lists -mtime +31 | xargs rm -f
#	@pushd data/exit-lists/; \
#		wget -r -nH -nd -nc --no-parent --reject "index.html*" \
#			$(collector_url)$(exit_lists_dir); \
#		popd
#	@echo Exit lists written

descriptors: data/descriptors/
	@echo "Getting latest descriptors (This may take a while)"
	@find data/descriptors -mtime +31 | xargs rm -f
	@pushd data/descriptors/; \
		wget -r -nH -nd -nc --no-parent --reject "index.html*" \
			$(collector_url)$(descriptors_dir); \
		popd
	@echo Done

data/cached-descriptors: descriptors
	@echo "Concatenating data/descriptors/* into data/cached-descriptors"
	@rm -f data/cached-descriptors
	find data/descriptors -type f -mmin -60 | xargs cat > data/cached-descriptors
	@echo "Done"

exits: data/consensus data/cached-descriptors # data/exit-addresses
	@echo Generating exit-policies file
	@python3 scripts/exitips.py
	@echo Done

data/langs: data/
	curl -k https://www.transifex.com/api/2/languages/ > data/langs

build:
	go build

# Add -i for installing latest version, -v for verbose
test: build
	! gofmt -l . 2>&1 | read
	go vet
	go test -v -run "$(filter)"

cover: build
	go test -coverprofile cover.out

filter?=.
bench: build
	go test -i
	go test -benchtime 10s -bench "$(filter)" -benchmem

profile: build
	go test \
		-cpuprofile ../../cpu.prof \
		-memprofile ../../mem.prof \
		-benchtime 40s -bench "$(filter)"

install: build
	mv check /usr/local/bin/check
	cp scripts/check.init /etc/init.d/check
	update-rc.d check defaults

.PHONY: start build i18n exits test bench cover profile descriptors install
