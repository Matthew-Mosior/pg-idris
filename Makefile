INTERACTIVE ?= --interactive

IDRIS := idris2

PACKAGE = pg-idris.ipkg

INDEXED_VERSION = 0.0.9
INDEXED_RELATIVE_DIR = indexed-${INDEXED_VERSION}
IDRIS_LIB_DIR := $(shell ${IDRIS} --libdir)

.PHONY: all deps build clean install test check-readme

all: deps build

./depends/${INDEXED_RELATIVE_DIR}:
	mkdir -p ./build/deps
	mkdir -p ./depends
	cd ./build/deps && \
	git clone https://github.com/mattpolzin/idris-indexed.git && \
	cd idris-indexed && \
	git checkout ${INDEXED_VERSION} && \
	make && \
	cp -R ./build/ttc ../../../depends/${INDEXED_RELATIVE_DIR}/

./depends/idris2-elab-util:
	mkdir -p ./build/deps
	mkdir -p ./depends
	cd ./build/deps && \
	git clone https://github.com/stefan-hoeck/idris2-elab-util.git && \
	cd idris2-elab-util && \
	$(IDRIS) --build elab-util.ipkg && \
	cp -R ./build/ttc ../../../depends/elab-util/

./depends/idris2-parser:
	mkdir -p ./build/deps
	mkdir -p ./depends
	cd ./build/deps && \
	git clone https://github.com/stefan-hoeck/idris2-parser.git && \
	cd idris2-parser && \
	$(IDRIS) --build parser.ipkg && \
	cp -R ./build/ttc ../../../depends/parser/

./depends/idris2-parser/json:
	mkdir -p ./build/deps
	mkdir -p ./depends
	cd ./build/deps && \
	cd idris2-parser/json && \
	$(IDRIS) --build parser-json.ipkg && \
	cp -R ./build/ttc ../../../../depends/json/

deps: ./depends/${INDEXED_RELATIVE_DIR} ./depends/idris2-elab-util ./depends/idris2-parser ./depends/idris2-parser/json

build:
	$(IDRIS) --build $(PACKAGE)

clean:
	rm -rf ./depends
	rm -rf ./build/deps
	rm -rf ./tests/build
	$(IDRIS) --clean $(PACKAGE)

install:
	$(IDRIS) --install $(PACKAGE)
	mkdir -p $(IDRIS_LIB_DIR)/${INDEXED_RELATIVE_DIR} && \
	cp -R ./depends/${INDEXED_RELATIVE_DIR} $(IDRIS_LIB_DIR)/ && \
	cp -R ./depends/elab-util/ $(IDRIS_LIB_DIR)/ && \
	cp -R ./depends/parser/ $(IDRIS_LIB_DIR)/ && \
	cp -R ./depends/json/ $(IDRIS_LIB_DIR)/
	
install-with-src:
	$(IDRIS) --install-with-src $(PACKAGE)
	mkdir -p $(IDRIS_LIB_DIR)/${INDEXED_RELATIVE_DIR} && \
	cp -R ./depends/${INDEXED_RELATIVE_DIR} $(IDRIS_LIB_DIR)/ && \
	cp -R ./depends/elab-util/ $(IDRIS_LIB_DIR)/ && \
	cp -R ./depends/parser/ $(IDRIS_LIB_DIR)/ && \
	cp -R ./depends/json/ $(IDRIS_LIB_DIR)/

test:
	cd tests && \
	$(IDRIS) --build pg-idris-tests.ipkg && \
	$(IDRIS) --install pg-idris-tests.ipkg && \
	./build/exec/test $(IDRIS) $(INTERACTIVE)

check-readme:
	idris2 -p indexed -p elab-util -p parser-json -p pg-idris --check README.md

