# NOTE: Every line in a recipe must begin with a tab character.
BUILD_DIR ?= target

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install

.PHONY: all clean test install

all: ;

process-resources:
	mkdir -p $(BUILD_DIR)
	rm -rf $(BUILD_DIR)/*

install: process-resources
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/zmq/
	$(INSTALL) src/lua/api-gateway/zmq/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/zmq/

test: process-resources
	echo "updating git submodules ..."
	if [ ! -d "test/resources/test-nginx/lib" ]; then	git submodule update --init --recursive; fi
	echo "running tests ..."
#	cp -r test/resources/api-gateway $(BUILD_DIR)
	PATH=/usr/local/sbin:$$PATH TEST_NGINX_SERVROOT=`pwd`/$(BUILD_DIR)/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl

test-docker: process-resources
	echo "running tests with docker ..."
	mkdir  -p $(BUILD_DIR)/test-logs
	rm -f $(BUILD_DIR)/test-logs/*
	mkdir -p ~/tmp/apiplatform/api-gateway-zmq-logger
	cp -r ./src ~/tmp/apiplatform/api-gateway-zmq-logger/
	cp -r ./test ~/tmp/apiplatform/api-gateway-zmq-logger/
	cp -r ./target ~/tmp/apiplatform/api-gateway-zmq-logger/
	cd ./test && docker-compose up
	cp -r ~/tmp/apiplatform/api-gateway-zmq-logger/target/ ./target
	rm -rf  ~/tmp/apiplatform/api-gateway-zmq-logger

package:
	git tag -a v0.1.0 -m 'release-0.1.0'
	git push origin v0.1.0
	git archive --format=tar --prefix=api-gateway-zmq-logger-0.1.0/ -o api-gateway-zmq-logger-0.1.0.tar.gz -v HEAD

clean: all
	rm -rf $(BUILD_DIR)/servroot